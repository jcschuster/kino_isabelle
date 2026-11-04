defmodule Mix.Tasks.KinoIsabelle.GenSyntax do
  @shortdoc "Regenerates priv/keywords.json and priv/symbols.json from Isabelle"
  @moduledoc """
  Regenerates the static syntax assets from the local Isabelle installation.

      mix kino_isabelle.gen_syntax [LOGIC]

  `priv/keywords.json` holds the outer-syntax keyword table of `LOGIC`
  (default `HOL`), taken from the same source as the Isabelle/VSCode grammar.
  `priv/symbols.json` holds the symbols of `$ISABELLE_HOME/etc/symbols` that
  have a Unicode code point. Rebuild the JS assets afterwards.
  """

  use Mix.Task

  @scala """
  import isabelle._

  object Keywords_JSON {
    def main(args: Array[String]): Unit = {
      val keywords =
        Sessions.background(Options.init(), args(0)).check_errors.base.overall_syntax.keywords
      val major =
        keywords.major.iterator.toList.sorted.map(k => JSON.Format(k) + ":" + JSON.Format(keywords.kinds(k)))
      val minor = keywords.minor.iterator.toList.sorted.map(JSON.Format(_))
      println("{\\"major\\":{" + major.mkString(",") + "},\\"minor\\":[" + minor.mkString(",") + "]}")
    }
  }
  """

  @impl true
  def run(args) do
    logic = List.first(args, "HOL")
    {:ok, isabelle} = IsabelleClient.Server.executable()

    write!("priv/keywords.json", keywords(isabelle, logic))
    write!("priv/symbols.json", symbols(isabelle))
  end

  defp keywords(isabelle, logic) do
    dir = Path.join(System.tmp_dir!(), "kino_isabelle_gen_syntax")
    File.mkdir_p!(dir)
    script = Path.join(dir, "keywords.scala")
    File.write!(script, @scala)

    case System.cmd(isabelle, ["scala", script, logic], cd: dir) do
      {out, 0} -> JSON.decode!(out)
      {out, status} -> Mix.raise("isabelle scala exited with #{status}:\n#{out}")
    end
  end

  defp symbols(isabelle) do
    {home, 0} = System.cmd(isabelle, ["getenv", "-b", "ISABELLE_HOME"])

    home
    |> String.trim()
    |> Path.join("etc/symbols")
    |> File.stream!()
    |> Enum.flat_map(&symbol/1)
  end

  defp symbol(line) do
    case String.split(line) do
      ["\\<" <> _ = name | fields] -> symbol(name, Enum.chunk_every(fields, 2))
      _ -> []
    end
  end

  defp symbol(name, fields) do
    case for(["code:", "0x" <> hex] <- fields, do: String.to_integer(hex, 16)) do
      [code] -> [[name, code, for(["abbrev:", abbrev] <- fields, do: abbrev)]]
      [] -> []
    end
  end

  defp write!(path, data) do
    File.write!(path, JSON.encode!(data))
    Mix.shell().info("wrote #{path}")
  end
end
