defmodule KinoIsabelle.Cell do
  @moduledoc false

  use Kino.JS, assets_path: "lib/assets/cell/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "Isabelle theory"

  alias KinoIsabelle.Result

  @defaults %{
    "variable" => "result",
    "text" => "",
    "session" => "HOL",
    "theory" => "Scratch",
    "imports" => ["Main"],
    "header_mode" => "auto"
  }

  @impl true
  def init(attrs, ctx) do
    fields =
      @defaults
      |> Map.merge(Map.take(attrs, Map.keys(@defaults)))
      |> Map.put("variable", Kino.SmartCell.prefixed_var_name("result", attrs["variable"]))

    {:ok, assign(ctx, fields: fields, check: nil, result: nil)}
  end

  @impl true
  def handle_connect(ctx) do
    %{fields: fields, check: check, result: result} = ctx.assigns
    {:ok, %{fields: fields, checking: check != nil, result: result}, ctx}
  end

  @impl true
  def handle_event("update", fields, ctx), do: {:noreply, update_fields(ctx, fields)}

  def handle_event("check", fields, ctx) do
    ctx = update_fields(ctx, fields)

    if ctx.assigns.check do
      {:noreply, ctx}
    else
      %{"text" => text} = attrs = ctx.assigns.fields

      task =
        Task.Supervisor.async_nolink(KinoIsabelle.TaskSupervisor, fn ->
          KinoIsabelle.check(text, options(attrs))
        end)

      broadcast_event(ctx, "checking", %{})
      {:noreply, assign(ctx, check: task.ref)}
    end
  end

  @impl true
  def handle_info({ref, reply}, %{assigns: %{check: ref}} = ctx) do
    Process.demonitor(ref, [:flush])
    {:noreply, ctx |> assign(check: nil) |> show(reply)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{assigns: %{check: ref}} = ctx),
    do: {:noreply, ctx |> assign(check: nil) |> show({:error, reason})}

  def handle_info({:evaluated, result}, ctx), do: {:noreply, show(ctx, {:ok, result})}

  @impl true
  def scan_eval_result(server, {:ok, %Result{} = result}), do: send(server, {:evaluated, result})
  def scan_eval_result(_server, _eval_result), do: :ok

  @impl true
  def to_attrs(ctx), do: ctx.assigns.fields

  @impl true
  def to_source(%{"variable" => variable, "text" => text} = attrs) do
    options =
      Enum.map_join(options(attrs), ",\n    ", fn {key, value} -> "#{key}: #{inspect(value)}" end)

    """
    {:ok, #{variable}} =
      KinoIsabelle.check(
        #{literal(text)},
        #{options}
      )

    #{variable}\
    """
  end

  defp options(%{"header_mode" => "manual"} = attrs),
    do: [session: attrs["session"], header_mode: :manual]

  defp options(attrs),
    do: [session: attrs["session"], theory: attrs["theory"], imports: attrs["imports"]]

  # A ~S heredoc keeps backslashes (\<forall>) and #{ verbatim; it cannot hold
  # """ at a line start, and \""" is read as an escaped delimiter.
  defp literal(text) do
    if String.contains?(text, ~s(""")) do
      inspect(text)
    else
      body =
        text
        |> String.trim_trailing("\n")
        |> String.split("\n")
        |> Enum.map_join("\n", &if(&1 == "", do: "", else: "    " <> &1))

      ~s(~S"""\n#{body}\n    """)
    end
  end

  defp update_fields(ctx, fields) do
    fields = Map.take(fields, Map.keys(@defaults))

    fields =
      if Map.has_key?(fields, "variable") and not variable?(fields["variable"]) do
        broadcast_event(ctx, "variable", %{variable: ctx.assigns.fields["variable"]})
        Map.delete(fields, "variable")
      else
        fields
      end

    assign(ctx, fields: Map.merge(ctx.assigns.fields, fields))
  end

  # Kino's check also admits nil, true, false and names starting with _,
  # which cannot be bound and returned.
  defp variable?(name) do
    Kino.SmartCell.valid_variable_name?(name) and name not in ~w(nil true false) and
      not String.starts_with?(name, "_")
  end

  defp show(ctx, reply) do
    payload = payload(reply)
    broadcast_event(ctx, "result", payload)
    assign(ctx, result: payload)
  end

  defp payload({:ok, %Result{} = result}),
    do: %{status: result.status, text: result.text, messages: result.messages}

  defp payload({:error, reason}), do: %{status: :error, error: error(reason), messages: []}

  defp error(:isabelle_not_found), do: "isabelle executable not found (set ISABELLE_TOOL or PATH)"
  defp error(:missing_theory_header), do: "manual header mode needs a theory header"

  defp error({:server_failed, status, output}),
    do: "isabelle server exited with status #{status}:\n#{output}"

  defp error({:server_timeout, output}),
    do: "isabelle server did not start within a minute:\n#{output}"

  defp error({:session_start_failed, logic, messages}),
    do: Enum.join(["could not start session #{logic}" | messages], "\n")

  defp error(reason), do: inspect(reason)
end
