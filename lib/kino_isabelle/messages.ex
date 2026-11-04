defmodule KinoIsabelle.Messages do
  @moduledoc """
  Normalises `use_theories` messages to `%{kind, text, from, to}` with cell
  offsets, and buckets them by command span.
  """

  alias KinoIsabelle.{Positions, Syntax}

  @type message :: %{
          kind: :error | :warning | :writeln,
          text: String.t(),
          from: non_neg_integer(),
          to: non_neg_integer()
        }

  @doc """
  Messages of a finished `use_theories` result, or of a failed task (an error in
  the theory header), ordered by position.

  Errors reported for other files (imported theories) are kept without position.
  """
  def normalize(%{"nodes" => nodes} = result, theory, table) do
    own = for node <- nodes, own?(node["node_name"], theory), msg <- node["messages"], do: msg

    foreign =
      for error <- Map.get(result, "errors", []),
          not own?(get_in(error, ["pos", "file"]), theory),
          do: Map.delete(error, "pos")

    (own ++ foreign)
    |> Enum.map(&message(&1, table))
    |> Enum.sort_by(& &1.from)
  end

  def normalize(%{"kind" => kind, "message" => yxml}, theory, table) do
    {text, positions} = decode(yxml)
    pos = Enum.find(positions, &own?(&1["file"], theory))
    [message(%{"kind" => kind, "message" => text, "pos" => pos}, table)]
  end

  @doc """
  Groups messages by the command span they start in. Returns the non-empty
  spans in order, each with its 1-based line and the command's first line.
  """
  def bucket(messages, text) do
    spans =
      text
      |> Syntax.command_offsets()
      |> Enum.map(&span(text, &1))
      |> then(&[span(text, 0) | &1])
      |> Enum.dedup_by(& &1.from)

    spans
    |> Enum.zip(Enum.map(tl(spans), & &1.from) ++ [:infinity])
    |> Enum.map(fn {span, to} ->
      Map.put(span, :messages, Enum.filter(messages, &(&1.from >= span.from and &1.from < to)))
    end)
    |> Enum.reject(&(&1.messages == []))
  end

  defp span(text, byte) do
    prefix = binary_part(text, 0, byte)
    [command | _] = text |> binary_part(byte, byte_size(text) - byte) |> String.split("\n")

    %{
      from: Positions.utf16_offset(text, byte),
      line: length(:binary.matches(prefix, "\n")) + 1,
      command: String.trim(command)
    }
  end

  defp message(msg, table) do
    {from, to} = Positions.range(table, msg["pos"])
    {text, _positions} = decode(msg["message"])
    %{kind: kind(msg["kind"]), text: text, from: from, to: to}
  end

  defp kind("error"), do: :error
  defp kind(kind) when kind in ["warning", "legacy"], do: :warning
  defp kind(_kind), do: :writeln

  defp own?(file, theory) when is_binary(file),
    do: Path.basename(file) == Path.basename(theory.path)

  defp own?(nil, _theory), do: false

  # YXML: elements are \x05\x06name\x06attr=value…\x05 … \x05\x06\x05. Report
  # markup carries data, not text, and is dropped with its body.
  defp decode(yxml) do
    {text, _stack, positions} =
      yxml
      |> String.split("\x05")
      |> Enum.reduce({[], [], []}, fn
        "\x06", {text, [_ | stack], positions} ->
          {text, stack, positions}

        "\x06" <> tag, {text, stack, positions} ->
          [name | attrs] = String.split(tag, "\x06")
          positions = if name == "position", do: [attributes(attrs) | positions], else: positions
          {text, [name | stack], positions}

        piece, {text, stack, positions} ->
          if Enum.any?(stack, &(&1 in ["report", "no_report"])),
            do: {text, stack, positions},
            else: {[text, piece], stack, positions}
      end)

    {IO.iodata_to_binary(text), Enum.reverse(positions)}
  end

  defp attributes(attrs) do
    Map.new(attrs, fn attr ->
      [key, value] = String.split(attr, "=", parts: 2)

      case Integer.parse(value) do
        {int, ""} -> {key, int}
        _ -> {key, value}
      end
    end)
  end
end
