defmodule KinoIsabelle.MixProject do
  use Mix.Project

  @version "0.1.0-alpha.1"
  @source_url "https://github.com/jcschuster/kino_isabelle"

  def project do
    [
      app: :kino_isabelle,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Livebook smart cell for Isabelle theories",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      mod: {KinoIsabelle.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:kino, "~> 0.19"},
      {:isabelle_elixir, "~> 0.4"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  # lib/mix/tasks is left out: gen_syntax regenerates priv/ of this repository.
  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Isabelle" => "https://isabelle.in.tum.de"},
      files: [
        "lib/kino_isabelle.ex",
        "lib/kino_isabelle",
        "lib/assets/cell/build",
        "priv",
        "mix.exs",
        ".formatter.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "livebooks/demo.livemd", "CHANGELOG.md", "LICENSE"],
      filter_modules: fn module, _metadata -> module != Mix.Tasks.KinoIsabelle.GenSyntax end,
      groups_for_modules: [
        Internals: [
          KinoIsabelle.Messages,
          KinoIsabelle.Output,
          KinoIsabelle.Positions,
          KinoIsabelle.Session,
          KinoIsabelle.Theory
        ]
      ]
    ]
  end
end
