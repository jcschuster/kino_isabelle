defmodule KinoIsabelle.Positions do
  @moduledoc """
  Maps Isabelle positions to offsets in the cell text.

  Isabelle reports `offset` and `end_offset` as 1-based symbol indices into the
  whole theory file, `end_offset` exclusive. A symbol is a `\\<name>` sequence
  or a single code point. Cell offsets are UTF-16 code units, as used by
  CodeMirror. Positions inside the prepended header map to 0, positions past
  the cell text (the appended `end`) map to the end of the text.
  """

  defstruct [:starts, :header]

  @symbol ~r/\\<\^?[A-Za-z][A-Za-z0-9_']*>|./us

  @doc "Builds the table for `text`, preceded by `header_symbols` symbols on disk."
  def new(text, header_symbols) do
    starts =
      @symbol
      |> Regex.scan(text)
      |> Enum.scan(0, fn [symbol], acc -> acc + utf16_length(symbol) end)

    %__MODULE__{starts: List.to_tuple([0 | starts]), header: header_symbols}
  end

  @doc "Number of Isabelle symbols in `text`."
  def symbol_count(text), do: @symbol |> Regex.scan(text) |> length()

  @doc """
  Converts an Isabelle position map to `{from, to}`.

  A missing or empty `end_offset` extends the range to one symbol; a missing
  position yields `{0, 0}`.
  """
  def range(%__MODULE__{} = table, %{"offset" => offset} = pos) when is_integer(offset) do
    from = index(table, offset)

    to =
      case pos do
        %{"end_offset" => end_offset} when is_integer(end_offset) and end_offset > offset ->
          index(table, end_offset)

        _ ->
          from + 1
      end

    {offset(table, from), offset(table, max(to, from + 1))}
  end

  def range(%__MODULE__{}, _pos), do: {0, 0}

  @doc "Converts a byte offset in `text` to a UTF-16 offset."
  def utf16_offset(text, byte_offset),
    do: text |> binary_part(0, byte_offset) |> utf16_length()

  defp index(%__MODULE__{header: header}, offset), do: offset - 1 - header

  defp offset(%__MODULE__{starts: starts}, index),
    do: elem(starts, index |> max(0) |> min(tuple_size(starts) - 1))

  defp utf16_length(text),
    do: text |> :unicode.characters_to_binary(:utf8, :utf16) |> byte_size() |> div(2)
end
