defmodule KinoIsabelle.Theory do
  @moduledoc """
  Turns cell text into a theory file.

  In `:auto` header mode the text is wrapped as
  `theory <theory> imports <imports> begin` … `end`; in `:manual` mode the text
  is a complete theory and its name is read from the header. All theories of a
  runtime share one directory, so a cell can import another cell's theory.
  """

  alias KinoIsabelle.Positions

  defstruct [:name, :dir, :path, :text, :source, :header_symbols]

  @header ~r/\A(?:\s|\(\*.*?\*\))*theory\s+"?([A-Za-z][A-Za-z0-9_'-]*)/s

  @doc "Builds the theory for `text`. Options: `:theory`, `:imports`, `:header_mode`."
  def new(text, opts) do
    body = String.trim_trailing(text)

    case Keyword.get(opts, :header_mode, :auto) do
      :auto ->
        name = Keyword.get(opts, :theory, "Scratch")
        imports = opts |> Keyword.get(:imports, ["Main"]) |> Enum.map_join(" ", &~s("#{&1}"))
        header = "theory #{name} imports #{imports} begin\n"
        {:ok, build(name, text, header <> body <> "\nend\n", Positions.symbol_count(header))}

      :manual ->
        case Regex.run(@header, text) do
          [_, name] -> {:ok, build(name, text, body <> "\n", 0)}
          nil -> {:error, :missing_theory_header}
        end
    end
  end

  @doc "Writes the theory file."
  def write!(%__MODULE__{} = theory) do
    File.mkdir_p!(theory.dir)
    File.write!(theory.path, theory.source)
  end

  defp build(name, text, source, header_symbols) do
    dir = Path.join(System.tmp_dir!(), "kino_isabelle_#{System.pid()}")

    %__MODULE__{
      name: name,
      dir: dir,
      path: Path.join(dir, name <> ".thy"),
      text: text,
      source: source,
      header_symbols: header_symbols
    }
  end
end
