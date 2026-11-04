defmodule KinoIsabelle.Output do
  @moduledoc "Builds `KinoIsabelle.Result`s and their Kino output."

  alias KinoIsabelle.{Messages, Positions, Result, Theory}

  @doc "Builds the result for `theory` from a raw `use_theories` or failed-task result."
  def result(%Theory{} = theory, raw) do
    table = Positions.new(theory.text, theory.header_symbols)

    %Result{
      status: if(raw["ok"] == true, do: :ok, else: :failed),
      theory: theory.name,
      text: theory.text,
      messages: Messages.normalize(raw, theory, table),
      node_status: node_status(raw, theory),
      raw: raw
    }
  end

  @doc "Summary, Messages, Errors and Raw tabs."
  def tabs(%Result{} = result) do
    errors = Enum.filter(result.messages, &(&1.kind == :error))

    Kino.Layout.tabs(
      Summary: Kino.Markdown.new(summary(result)),
      Messages: listing(result.messages, result.text),
      Errors: listing(errors, result.text),
      Raw: Kino.Tree.new(result.raw)
    )
  end

  defp node_status(%{"nodes" => nodes}, theory) do
    Enum.find_value(nodes, fn node ->
      Path.basename(node["node_name"]) == Path.basename(theory.path) && node["status"]
    end)
  end

  defp node_status(_raw, _theory), do: nil

  defp summary(result) do
    counts = Enum.frequencies_by(result.messages, & &1.kind)
    status = if result.status == :ok, do: "✅ ok", else: "❌ failed"

    progress =
      case result.node_status do
        %{"finished" => finished, "failed" => failed, "total" => total} ->
          " — #{finished}/#{total} commands finished, #{failed} failed"

        nil ->
          ""
      end

    """
    **#{result.theory}**: #{status}#{progress}

    Errors: #{counts[:error] || 0} · Warnings: #{counts[:warning] || 0} · \
    Other messages: #{counts[:writeln] || 0}
    """
  end

  defp listing([], _text), do: Kino.Text.new("No messages.")

  defp listing(messages, text) do
    messages
    |> Messages.bucket(text)
    |> Enum.map_join("\n\n", fn span ->
      Enum.map_join(span.messages, "\n", &"  [#{&1.kind}] #{indent(&1.text)}")
      |> then(&"line #{span.line}: #{span.command}\n#{&1}")
    end)
    |> Kino.Text.new(terminal: true)
  end

  defp indent(text), do: String.replace(text, "\n", "\n    ")
end

defimpl Kino.Render, for: KinoIsabelle.Result do
  def to_livebook(result),
    do: result |> KinoIsabelle.Output.tabs() |> Kino.Render.to_livebook()
end
