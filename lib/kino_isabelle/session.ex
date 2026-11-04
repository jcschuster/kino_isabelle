defmodule KinoIsabelle.Session do
  @moduledoc """
  The runtime's Isabelle server and its logic sessions.

  The server is started on the first check and each logic session (`"HOL"`, …)
  on the first check that names it. Both live as long as this process: a
  watchdog kills the server when this process or the whole VM exits. If the
  connection dies, this process exits and its supervisor restarts it, so the
  next check starts afresh.

  The last result per theory file is cached and returned while the source and
  logic session are unchanged.
  """

  use GenServer

  alias IsabelleClient.Shared
  alias KinoIsabelle.Theory

  @server_timeout 60_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Writes and checks `theory` in the logic session `logic`.

  Returns the raw `use_theories` result, or the failed task's result when
  Isabelle rejects the theory header.
  """
  def use_theories(logic, %Theory{} = theory) do
    key = {logic, theory.path}

    case GenServer.call(__MODULE__, {:prepare, logic, key, theory.source}, :infinity) do
      {:cached, result} ->
        {:ok, result}

      {:run, client, session_id} ->
        Theory.write!(theory)

        args = [
          session_id: session_id,
          theories: [theory.name],
          master_dir: theory.dir,
          unicode_symbols: true
        ]

        with {:ok, result} <- task_result(Shared.use_theories(client, args)) do
          GenServer.cast(__MODULE__, {:cache, key, theory.source, result})
          {:ok, result}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp task_result({:ok, %IsabelleClient.Task{result: result}}), do: {:ok, result}
  defp task_result({:error, %IsabelleClient.Task{result: result}}), do: {:ok, result}
  defp task_result({:error, reason}), do: {:error, reason}

  @impl true
  def init(nil) do
    Process.flag(:trap_exit, true)
    {:ok, %{client: nil, sessions: %{}, cache: %{}}}
  end

  @impl true
  def handle_call({:prepare, logic, key, source}, _from, state) do
    case state.cache do
      %{^key => {^source, result}} ->
        {:reply, {:cached, result}, state}

      _ ->
        case ensure_session(state, logic) do
          {:ok, state} -> {:reply, {:run, state.client, state.sessions[logic]}, state}
          {:error, reason, state} -> {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_cast({:cache, key, source, result}, state),
    do: {:noreply, put_in(state.cache[key], {source, result})}

  @impl true
  def handle_info({:EXIT, client, reason}, %{client: client} = state),
    do: {:stop, reason, %{state | client: nil}}

  # Exit of a client whose start failed, or of a closed port.
  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}
  def handle_info({_port, :closed}, state), do: {:noreply, state}

  defp ensure_session(%{sessions: sessions} = state, logic) when is_map_key(sessions, logic),
    do: {:ok, state}

  defp ensure_session(state, logic) do
    with {:ok, state} <- ensure_client(state) do
      case Shared.start_session(state.client, [session: logic], :infinity) do
        {:ok, task} ->
          {:ok, put_in(state.sessions[logic], task.result["session_id"])}

        {:error, %IsabelleClient.Task{} = task} ->
          {:error, {:session_start_failed, logic, IsabelleClient.Result.errors(task)}, state}

        {:error, reason} ->
          {:error, reason, state}
      end
    end
  end

  # The server name must be unique across VMs: `isabelle server -n` joins a
  # running server of the same name.
  defp ensure_client(%{client: nil} = state) do
    name = "kino_isabelle_#{System.pid()}_#{System.unique_integer([:positive])}"

    with {:ok, isabelle} <- IsabelleClient.Server.executable() do
      watchdog = watchdog(isabelle, name)

      with {:ok, info} <- start_server(isabelle, name),
           {:ok, client} <-
             Shared.start_link(password: info.password, host: info.host, port: info.port) do
        {:ok, %{state | client: client}}
      else
        {:error, reason} ->
          Port.close(watchdog)
          {:error, reason, state}
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp ensure_client(state), do: {:ok, state}

  # Instead of IsabelleClient.Server.start/2, which drops the server's stderr
  # and raises when the server exits before it closes the port.
  defp start_server(isabelle, name) do
    port =
      Port.open({:spawn_executable, isabelle}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["server", "-n", name, "-p", "0"]
      ])

    await_server(port, "")
  end

  defp await_server(port, output) do
    receive do
      {^port, {:data, data}} ->
        output = output <> data

        case IsabelleClient.Server.parse_info(output) do
          [info] ->
            # Unlike Port.close/1, does not raise if the server already exited.
            send(port, {self(), :close})
            {:ok, info}

          [] ->
            await_server(port, output)
        end

      {^port, {:exit_status, status}} ->
        {:error, {:server_failed, status, String.trim(output)}}
    after
      @server_timeout ->
        send(port, {self(), :close})
        {:error, {:server_timeout, String.trim(output)}}
    end
  end

  # Livebook halts a runtime without stopping applications, so cleanup cannot
  # rely on terminate/2. The port's stdin closes when its owner or the VM
  # exits; `read` then returns and the server is killed.
  defp watchdog(isabelle, name) do
    Port.open({:spawn_executable, "/bin/sh"},
      args: ["-c", ~s(read _; exec "$0" server -n "$1" -x >/dev/null 2>&1), isabelle, name]
    )
  end
end
