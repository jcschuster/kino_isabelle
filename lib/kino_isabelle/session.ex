defmodule KinoIsabelle.Session do
  @moduledoc """
  The runtime's Isabelle server and its logic sessions.

  The server is started on the first check and each logic session (`"HOL"`, …)
  on the first check that names it. Both live until the runtime stops; the
  server is shut down in `terminate/2`. If the connection dies, this process
  exits and its supervisor restarts it, so the next check starts afresh.

  The last result per theory file is cached and returned while the source and
  logic session are unchanged.
  """

  use GenServer

  alias IsabelleClient.Shared
  alias KinoIsabelle.Theory

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

  # Exit of a client whose start failed; the error was already returned.
  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{client: nil}), do: :ok
  def terminate(_reason, %{client: client}), do: Shared.close(client)

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

  defp ensure_client(%{client: nil} = state) do
    case Shared.start_link([]) do
      {:ok, client} -> {:ok, %{state | client: client}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp ensure_client(state), do: {:ok, state}
end
