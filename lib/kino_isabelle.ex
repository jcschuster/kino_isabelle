defmodule KinoIsabelle do
  @moduledoc """
  Livebook smart cell for Isabelle theories.

  The "Isabelle theory" smart cell edits theory text and checks it with
  `check/2` on the runtime's shared Isabelle server.
  """

  alias KinoIsabelle.{Output, Session, Theory}

  @doc """
  Checks `text` as an Isabelle theory.

  Options:

    * `:session` - logic session, default `"HOL"`
    * `:theory` - theory name, default `"Scratch"`
    * `:imports` - imported theories, default `["Main"]`
    * `:header_mode` - `:auto` (default) wraps `text` in a theory header using
      `:theory` and `:imports`; `:manual` expects a complete theory

  Returns `{:ok, result}` also when the theory has errors; `{:error, reason}`
  when Isabelle could not be run.
  """
  @spec check(String.t(), keyword()) :: {:ok, KinoIsabelle.Result.t()} | {:error, term()}
  def check(text, opts \\ []) do
    with {:ok, theory} <- Theory.new(text, opts),
         {:ok, raw} <- Session.use_theories(Keyword.get(opts, :session, "HOL"), theory) do
      {:ok, Output.result(theory, raw)}
    end
  end

  @doc """
  Sets the Isabelle server that checks run on.

  `:local`, the default, starts a server on the first check. A keyword list
  connects to a running server; its keys are those of
  `config :kino_isabelle, :server` (see the README): `:password`, either
  `:url` or `:port` and `:host`, and `:sessions`.

  A setting other than the current one restarts `KinoIsabelle.Session`: the
  runtime drops its connection and logic sessions, a local server is stopped,
  and the next check uses the new setting.
  """
  @spec use_server(:local | keyword()) :: :ok
  def use_server(server) do
    if server != Application.get_env(:kino_isabelle, :server, :local) do
      Application.put_env(:kino_isabelle, :server, server)
      Session.restart()
    end

    :ok
  end
end
