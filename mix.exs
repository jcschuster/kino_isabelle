defmodule KinoIsabelle.MixProject do
  use Mix.Project

  def project do
    [
      app: :kino_isabelle,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {KinoIsabelle.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:kino, "~> 0.19"},
      {:isabelle_elixir, "~> 0.4"}
    ]
  end
end
