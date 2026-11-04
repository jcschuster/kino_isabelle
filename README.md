# KinoIsabelle

Livebook smart cell for [Isabelle](https://isabelle.in.tum.de) theories: a
CodeMirror editor with Isabelle outer-syntax highlighting and symbol display,
checked on demand by a local Isabelle server.

This is an alpha release: expect rough edges and breaking changes.

## Installation

```elixir
Mix.install([
  {:kino_isabelle, "~> 0.1.0-alpha.1"}
])
```

Isabelle must be installed, with `isabelle` on `PATH` or `ISABELLE_TOOL`
pointing to it. Tested with Isabelle2025-2. A logic session without a built
heap is built on first use, which can take long. Server cleanup relies on
`/bin/sh`, so Windows is not supported.

Isabelle also needs `tar` on the `PATH` of the Livebook runtime; without it,
the server fails with `Return code 1 from bash script: ".../gnu-utils-.../etc/settings"`.
The NixOS `services.livebook` service, for example, has no `tar` on its `PATH`;
add `pkgs.gnutar` to `services.livebook.extraPackages`.

## Usage

[`livebooks/demo.livemd`](livebooks/demo.livemd) walks through the cell.

Add the **Isabelle theory** smart cell and write theory text. By default the
cell generates the header (`theory Scratch imports Main begin` … `end`) from
the toolbar fields; with header mode "in text" the cell holds a complete
theory.

- **Check** runs Isabelle on the current text. Errors and warnings appear as
  lint diagnostics; the panel below the editor shows all messages of the
  command under the cursor. Nothing is checked while typing.
- **Evaluating the cell** returns a `KinoIsabelle.Result`, shown as
  Summary / Messages / Errors / Raw tabs, and binds it to the variable in
  **Assign to** (`result`, `result2`, … by default). An unchanged theory is
  not checked twice.
- Symbols such as `\<forall>` are displayed as `∀`. Type `\forall`, `\<forall`
  or an abbreviation like `==>` and pick the symbol from the completion list.

The first check of a runtime starts the Isabelle server and the logic session.
They are shared by all cells of the runtime and stopped with it. All theories
of a runtime are written to one directory, so a cell can import the theory of
another cell that was checked before.

Without the smart cell:

```elixir
{:ok, result} = KinoIsabelle.check(~S(lemma "\<forall>x. x = x" by simp), imports: ["Main"])
```

## Development

```sh
mix test                          # includes Isabelle integration tests when isabelle is found
cd assets && npm install && npm test
npm run build                     # rebuilds lib/assets/cell/build (committed), including
                                  # THIRD_PARTY_LICENSES.txt for the bundled npm packages
mix kino_isabelle.gen_syntax HOL  # regenerates priv/keywords.json and priv/symbols.json
```

The keyword table is generated for one logic (HOL); keywords that other
sessions add are not highlighted. After regenerating it, rebuild the assets.

## License

MIT, see [LICENSE](LICENSE). The bundled editor code (CodeMirror and its
dependencies, all MIT) comes with its licenses in
`lib/assets/cell/build/THIRD_PARTY_LICENSES.txt`.
