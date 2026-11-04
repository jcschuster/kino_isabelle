# kino_isabelle — Plan

Livebook smart cell for Isabelle: a CodeMirror 6 editor for theory text, explicit evaluation through `isabelle_elixir`, outputs routed back to the editor by position.

Hex package `kino_isabelle`, module namespace `KinoIsabelle`. Standalone package; not part of Loge.

## Scope

- Smart cell "Isabelle theory" with a CodeMirror 6 editor (own bundle, not Livebook's managed editor).
- Outer-syntax highlighting; inner syntax (quoted terms) tokenised only as strings and `\<symbol>`s.
- Isabelle symbol display (`\<forall>` rendered as `∀`) and abbreviation input.
- Explicit evaluation only: a Check button (and the cell's own Evaluate) runs `use_theories`; no checking on edit.
- Errors and warnings as CodeMirror lint diagnostics.
- An output panel inside the cell showing the messages of the command under the cursor (jEdit-style).
- Cell output below the cell: status summary and the full message list ordered by position.
- One Isabelle server and session per Livebook runtime, started lazily.

## Non-goals

- Live checking while typing.
- PIDE-style proof state at the cursor, hyperlinked output, markup beyond plain-text messages.
- Inner-syntax highlighting.
- Session builds (`session_build`), export retrieval, multi-theory projects.
- Inline output widgets between commands (panel chosen instead).

## Architecture

### Elixir

- `KinoIsabelle.Cell` — `Kino.SmartCell` + `Kino.JS.Live`. Owns attrs, handles editor events, triggers checks, broadcasts results to the editor, emits the generated source.
- `KinoIsabelle.Session` — supervised process wrapping `IsabelleClient.Shared`. Starts the server and the configured logic session on first use, keeps them for the runtime's lifetime, restarts on failure. One per runtime, registered by name.
- `KinoIsabelle.Theory` — turns cell text into a theory file on disk: temp directory per cell, theory name and imports from attrs or from the user's own header. Records how many header lines were prepended so positions can be shifted back.
- `KinoIsabelle.Positions` — converts Isabelle positions (`line`, `offset`, `end_offset`, symbol-based) to character offsets in the cell text, accounting for prepended header lines and the symbol encoding of the text on disk.
- `KinoIsabelle.Messages` — normalises `use_theories` messages into `%{kind, text, from, to}`; buckets them by command span.
- `KinoIsabelle.Output` — builds the Kino output (`Kino.Layout.tabs`: Summary / Messages / Errors / Raw) and the result struct returned by the cell.
- `KinoIsabelle.check/2` — public entry point used by the generated source: `check(theory_text, opts) :: {:ok, result} | {:error, reason}`.

### JavaScript (assets)

- CodeMirror 6 editor with:
  - outer-syntax `StreamLanguage` mode (commands, keywords, comments, cartouches, strings, `\<symbol>` tokens);
  - command-span tracking: every command keyword starts a span; spans are computed from the token stream and kept in editor state;
  - symbol display via replacing decorations backed by Isabelle's `etc/symbols` table; abbreviation input (`\forall`, `==>` …) via `@codemirror/autocomplete`;
  - `@codemirror/lint` source fed from the last check result (no automatic re-lint).
- Toolbar: Check button, session name, status indicator (idle / checking / ok / failed).
- Output panel: lists the messages whose range lies in the command span containing the cursor; empty state when the command has no output; updates on cursor move from cached results only.
- Position mapping on the JS side works in character offsets; the Elixir side delivers already-converted ranges.

## Evaluation flow

1. User presses Check (or evaluates the cell).
2. `KinoIsabelle.Cell` sends the current text to `KinoIsabelle.check/2`.
3. `KinoIsabelle.Theory` writes the theory file; `KinoIsabelle.Session` runs `use_theories` on the shared session.
4. Result: node status plus message list. `KinoIsabelle.Positions` maps positions; `KinoIsabelle.Messages` buckets by span.
5. Cell broadcasts `{:check_result, %{status, diagnostics, messages_by_span}}` to the editor: lint diagnostics are set, the panel refreshes.
6. The generated source produces the Kino output and returns the result struct.

Check button and cell evaluation share one path: the button triggers cell evaluation (as in Loge); the editor receives the result from the cell process, the notebook receives it from the generated source. The last result is cached in the cell process so the generated source does not re-run `use_theories` when nothing changed (keyed by text hash and session).

## Generated source

```elixir
KinoIsabelle.check(
  """
  <cell text>
  """,
  session: "HOL",
  theory: "Scratch",
  imports: ["Main"]
)
```

Attrs: `text`, `session`, `theory`, `imports`, `header_mode` (`:auto` wraps the body, `:manual` expects a full theory).

## Keyword source

Keyword list generated from Isabelle's keyword table for the default session (same source the Isabelle/VSCode grammar is generated from), stored as a static JSON asset. Regeneration is a mix task, not a runtime step. Session-specific keywords are out of scope for the first version.

## Status

Legend: `[x]` done and verified, `[~]` written but not verified, `[ ]` not started.

### Open questions (smoke-tested against Isabelle2025-2, `isabelle_elixir` 0.4.1)

- [x] Library version: using `~> 0.4` instead of 0.3 (0.4.0 fixes reply desync after timeouts in `Shared`; needs Elixir 1.20, which the project already requires). Entry point is `IsabelleClient.Shared.use_theories(pid, args)`; `unicode_symbols: true` works. `check_limit` not tested.
- [x] Positions: `offset` and `end_offset` are 1-based symbol indices into the whole file, `end_offset` exclusive; `line` is 1-based. Some messages have `end_offset == offset` (e.g. "Malformed command syntax") or no `end_offset` (header errors); both are widened to one symbol.
- [x] Input encoding: the server accepts raw UTF-8 (`∀`) as well as `\<forall>`, so the text is written as is. Assumed: one code point = one symbol. Not verified for astral-plane characters (`𝔄` checks fine, but its offsets were not inspected).
- [x] Outputs: `thm`, `value`, `term`, `nitpick`, `try0` all report `writeln` messages with positions. `sledgehammer` not tested.
- [x] Re-running an unchanged theory returns the same messages, so the cache is a pure optimisation.
- [x] Header errors (bad theory name, missing import, no header) arrive as `{:error, %Task{status: :failed}}` whose message is YXML with the position in a `position` element. `Messages` decodes this.
- [x] Unknown logic: `session_start` fails after about 1 s with "Undefined session(s)".
- [~] Server lifecycle: `Session.terminate/2` closes the `Shared` client, which kills the server. Not verified on Livebook runtime reconnect or cell deletion.

### Milestones

1. [x] `KinoIsabelle.Session`, `KinoIsabelle.Theory`, `KinoIsabelle.check/2`, `KinoIsabelle.Output` (Summary / Messages / Errors / Raw tabs via `Kino.Render` on `KinoIsabelle.Result`). `check/2` verified from `mix run`; the tabs were not rendered in Livebook.
2. [~] Smart cell `KinoIsabelle.Cell` with CodeMirror 6 (`assets/`, built into `lib/assets/cell/build`). Bundle builds and Elixir compiles without warnings. Not yet opened in Livebook.
   - [x] Keyword source: `mix kino_isabelle.gen_syntax [LOGIC]` writes `priv/keywords.json` (same Scala query as the Isabelle/VSCode grammar, via `isabelle scala`) and `priv/symbols.json` (from `etc/symbols`).
   - [~] Outer-syntax `StreamLanguage` (`assets/js/isabelle.js`).
   - [~] Toolbar: Check button, session / header mode / theory / imports fields, status indicator.
3. [~] Position mapping (`KinoIsabelle.Positions`, to UTF-16 offsets for CodeMirror) and lint diagnostics. Results arriving after further edits are mapped onto the current text by a prefix/suffix diff.
4. [~] Command spans and output panel. Elixir: `KinoIsabelle.Syntax` + `Messages.bucket/2`; JS: `commandSpan` over the syntax tree. The two scanners must stay in sync.
5. [~] Symbol display (replacing decorations, atomic ranges) and completion for `\name`, `\<name` and abbreviations of two or more characters.
6. [ ] Tests: none written yet. Planned: `Positions` (symbols, header shift, astral characters), `Syntax`/`Messages.bucket`, YXML decoding, `Cell.to_source` round trip (`~S` heredoc, text containing `"""`), and an integration test tagged `:isabelle` for the local server.

### Next steps

- [ ] Find the stall: one `mix run` script calling `check/2` several times (symbols, cache hit, manual header, bad import, unknown logic) did not return within 10 minutes. Each case returned promptly when run on its own (unknown logic in ~1 s), so the cause is still unknown. Possibly sequencing in `Session` or `Shared`.
- [ ] Open the cell in Livebook: editor, Check button, lint, panel, symbol display, completion, re-connect with a cached result.
- [ ] Write the tests from milestone 6.
- [ ] README: replace the `mix new` stub (usage, `ISABELLE_TOOL`, rebuilding assets with `npm run build` in `assets/`).

### Deviations from the plan, to decide

- [ ] Theory directory: all cells of a runtime share one directory (`$TMP/kino_isabelle_<os pid>`) so that cells can import each other, instead of one directory per cell. Two cells with the same theory name overwrite each other's file.
- [ ] The Check button checks in the cell process and pushes the result to the editor; it does not trigger cell evaluation (the Kino smart-cell API has no call for that). Cell evaluation runs `check/2` itself and reuses the cached result when the text is unchanged.
- [ ] Cache key is `{logic, theory file}` and stores the full source, not a hash.
