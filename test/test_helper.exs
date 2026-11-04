defmodule KinoIsabelle.TestHelpers do
  @doc "The part of `text` covered by UTF-16 offsets `from..to`."
  def slice(text, %{from: from, to: to}), do: slice(text, {from, to})

  def slice(text, {from, to}) do
    text
    |> :unicode.characters_to_binary(:utf8, :utf16)
    |> binary_part(from * 2, (to - from) * 2)
    |> :unicode.characters_to_binary(:utf16, :utf8)
  end
end

# Integration tests run against a local Isabelle when one is found.
isabelle? = match?({:ok, _}, IsabelleClient.Server.executable())
ExUnit.start(exclude: if(isabelle?, do: [], else: [:isabelle]))
