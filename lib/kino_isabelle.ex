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
end
