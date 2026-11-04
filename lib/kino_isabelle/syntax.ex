defmodule KinoIsabelle.Syntax do
  @moduledoc false
  # Outer-syntax scanner for command spans. Must agree with assets/js/isabelle.js.

  @external_resource keywords_path = Path.join(__DIR__, "../../priv/keywords.json")
  %{"major" => major, "minor" => minor} = keywords_path |> File.read!() |> JSON.decode!()

  @commands major |> Map.keys() |> MapSet.new()
  @symbolic (Map.keys(major) ++ minor)
            |> Enum.reject(&Regex.match?(~r/\A[A-Za-z]/, &1))
            |> Enum.sort_by(&byte_size/1, :desc)

  @ident ~r/\A[A-Za-z][A-Za-z0-9_']*(?:\.[A-Za-z][A-Za-z0-9_']*)*/
  @symbol ~r/\A\\<\^?[A-Za-z][A-Za-z0-9_']*>/
  @number ~r/\A[0-9]+(?:\.[0-9]+)?/

  @doc "Byte offsets of all command keywords in `text`, ascending."
  def command_offsets(text), do: scan(text, 0, [])

  defp scan(<<>>, _pos, acc), do: Enum.reverse(acc)
  defp scan("(*" <> rest, pos, acc), do: skip_comment(rest, pos + 2, 1, acc)
  defp scan("{*" <> rest, pos, acc), do: skip_until(rest, pos + 2, "*}", acc)
  defp scan("\"" <> rest, pos, acc), do: skip_quoted(rest, pos + 1, "\"", acc)
  defp scan("`" <> rest, pos, acc), do: skip_quoted(rest, pos + 1, "`", acc)
  defp scan("\\<open>" <> rest, pos, acc), do: skip_cartouche(rest, pos + 7, 1, acc)
  defp scan("‹" <> rest, pos, acc), do: skip_cartouche(rest, pos + 3, 1, acc)

  defp scan(text, pos, acc) do
    case Regex.run(@ident, text) || Regex.run(@number, text) || Regex.run(@symbol, text) ||
           symbolic(text) do
      [token] ->
        acc = if MapSet.member?(@commands, token), do: [pos | acc], else: acc
        size = byte_size(token)
        scan(binary_part(text, size, byte_size(text) - size), pos + size, acc)

      nil ->
        <<char::utf8, rest::binary>> = text
        scan(rest, pos + byte_size(<<char::utf8>>), acc)
    end
  end

  defp symbolic(text) do
    Enum.find_value(@symbolic, &(String.starts_with?(text, &1) && [&1]))
  end

  defp skip_comment(<<>>, _pos, _depth, acc), do: Enum.reverse(acc)
  defp skip_comment("*)" <> rest, pos, 1, acc), do: scan(rest, pos + 2, acc)

  defp skip_comment("*)" <> rest, pos, depth, acc),
    do: skip_comment(rest, pos + 2, depth - 1, acc)

  defp skip_comment("(*" <> rest, pos, depth, acc),
    do: skip_comment(rest, pos + 2, depth + 1, acc)

  defp skip_comment(<<_, rest::binary>>, pos, depth, acc),
    do: skip_comment(rest, pos + 1, depth, acc)

  defp skip_until(text, pos, stop, acc) do
    case :binary.match(text, stop) do
      {at, len} ->
        scan(binary_part(text, at + len, byte_size(text) - at - len), pos + at + len, acc)

      :nomatch ->
        Enum.reverse(acc)
    end
  end

  defp skip_quoted(<<>>, _pos, _quote, acc), do: Enum.reverse(acc)

  defp skip_quoted(<<?\\, _, rest::binary>>, pos, quote, acc),
    do: skip_quoted(rest, pos + 2, quote, acc)

  defp skip_quoted(<<q, rest::binary>>, pos, <<q>>, acc), do: scan(rest, pos + 1, acc)

  defp skip_quoted(<<_, rest::binary>>, pos, quote, acc),
    do: skip_quoted(rest, pos + 1, quote, acc)

  defp skip_cartouche(<<>>, _pos, _depth, acc), do: Enum.reverse(acc)

  defp skip_cartouche("\\<close>" <> rest, pos, depth, acc),
    do: close_cartouche(rest, pos + 8, depth, acc)

  defp skip_cartouche("›" <> rest, pos, depth, acc),
    do: close_cartouche(rest, pos + 3, depth, acc)

  defp skip_cartouche("\\<open>" <> rest, pos, depth, acc),
    do: skip_cartouche(rest, pos + 7, depth + 1, acc)

  defp skip_cartouche("‹" <> rest, pos, depth, acc),
    do: skip_cartouche(rest, pos + 3, depth + 1, acc)

  defp skip_cartouche(<<_, rest::binary>>, pos, depth, acc),
    do: skip_cartouche(rest, pos + 1, depth, acc)

  defp close_cartouche(rest, pos, 1, acc), do: scan(rest, pos, acc)
  defp close_cartouche(rest, pos, depth, acc), do: skip_cartouche(rest, pos, depth - 1, acc)
end
