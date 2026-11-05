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

### Open questions (tested against Isabelle2025-2, `isabelle_elixir` 0.4.1)

- [x] Library version: using `~> 0.4` instead of 0.3 (0.4.0 fixes reply desync after timeouts in `Shared`; needs Elixir 1.20, which the project already requires). Entry point is `IsabelleClient.Shared.use_theories(pid, args)`; `unicode_symbols: true` works. `check_limit` not tested.
- [x] Positions: `offset` and `end_offset` are 1-based symbol indices into the whole file, `end_offset` exclusive; `line` is 1-based. Some messages have `end_offset == offset` (e.g. "Malformed command syntax") or no `end_offset` (header errors); both are widened to one symbol.
- [x] Symbols are delimited as by Isabelle's `Symbol.Matcher`: one code point (also outside the BMP, e.g. emoji), `\r\n` as one symbol, `\<name>` also when malformed (`\<abc`). Checked against real offsets for emoji, combining marks, CJK, fraktur, named/control symbols, CRLF, CR, tab/form feed and a malformed symbol; these are the fixtures in `positions_test.exs`.
- [x] Input encoding: the server accepts raw UTF-8 (`∀`) as well as `\<forall>`, so the text is written as is.
- [x] Outputs: `thm`, `value`, `term`, `nitpick`, `try0` all report `writeln` messages with positions, on the command keyword. `sledgehammer` not tested.
- [x] Re-running an unchanged theory returns the same messages, so the cache is a pure optimisation.
- [x] Header errors (bad theory name, missing import, no header) arrive as `{:error, %Task{status: :failed}}` whose message is YXML with the position in a `position` element. `Messages` decodes this.
- [x] Unknown logic: `session_start` fails after about 1 s with "Undefined session(s)". A logic without a heap is built by `session_start` first.
- [x] Server start: `Session` runs `isabelle server` itself and connects `Shared` to it. `IsabelleClient.Server.start/2` drops the server's stderr and raises `badarg` from `Port.close` when the server exits early, so a failing start showed only `{:badarg, …}` (reported from a Livebook outside this container; cause not known yet). Now the error carries Isabelle's output.
- [x] Server lifecycle: Livebook's standalone runtime ends with `System.halt()` (Livebook 0.19.10, `runtime/standalone.ex`), so `terminate/2` never runs. `Session` instead owns a watchdog port (`/bin/sh`, waits for stdin EOF, then `isabelle server -x`). Verified: no server left after `System.halt()`, `System.stop()`, killing `Session`, or killing the client (Session restarts, next check starts a new server). Deleting a cell does not stop the server; it belongs to the runtime. Server names include the OS pid, since `isabelle server -n` joins a running server of the same name.

### Milestones

1. [x] `KinoIsabelle.Session`, `KinoIsabelle.Theory`, `KinoIsabelle.check/2`, `KinoIsabelle.Output` (Summary / Messages / Errors / Raw tabs via `Kino.Render` on `KinoIsabelle.Result`). Tabs render to Livebook output maps; not looked at in Livebook.
2. [~] Smart cell `KinoIsabelle.Cell` with CodeMirror 6 (`assets/`, built into `lib/assets/cell/build`).
   - [x] Keyword source: `mix kino_isabelle.gen_syntax [LOGIC]` writes `priv/keywords.json` (same Scala query as the Isabelle/VSCode grammar, via `isabelle scala`) and `priv/symbols.json` (from `etc/symbols`).
   - [x] Outer-syntax `StreamLanguage` (`assets/js/isabelle.js`), tested in Node.
   - [x] Cell process: attrs, `to_source`, Check event, evaluated result to editor, reconnect payload (`Kino.Test`).
   - [~] Toolbar and editor UI: checked in jsdom only (Check button, status, field sync, header-mode toggle, error payload, reconnect). Layout, styling and Livebook's real `ctx` not checked.
3. [x] Position mapping (`KinoIsabelle.Positions`, to UTF-16 offsets for CodeMirror) and lint diagnostics (jsdom). Results arriving after further edits are mapped onto the current text by a prefix/suffix diff (jsdom).
4. [x] Command spans and output panel. Elixir `KinoIsabelle.Syntax` and JS `commandSpan` are tested against the same fixture (`test/fixtures/commands.*`). Panel per cursor position checked in jsdom.
5. [~] Symbol display (replacing decorations, atomic ranges) and completion for `\name`, `\<name` and abbreviations of two or more characters. Completion tested in Node; display renders `∀` in jsdom; cursor movement over symbols not checked.
6. [x] Tests: `mix test` (37 tests; the 5 in `kino_isabelle_test.exs` are tagged `:isabelle` and run when an `isabelle` executable is found) and `npm test` in `assets/` (7 tests).

### Next steps

- [x] The stall: not a hang in the check path. A server outlived the `mix run` VM and held the inherited stderr pipe open, so `| tail` never finished. Fixed by the watchdog above.
- [x] Demo notebook `livebooks/demo.livemd`: Livebook 0.19.10 imports it without warnings and re-exports it unchanged; all its cells evaluate as described (outside Livebook, via `Mix.install` with the path dependency).
- [x] Opened in a browser by the user (2026-11-04): looks good. Not checked in detail: dark theme, keyboard handling, completion popup, cursor movement over symbol widgets.
- [x] Result variable: "Assign to" field (attr `variable`); new cells default to `result`, `result2`, … via `Kino.SmartCell.prefixed_var_name/2`. Invalid names (Kino's check plus `nil`/`true`/`false` and a leading `_`) are rejected and the field is reset.
- [x] README.
- [x] Packaging for 0.1.0-alpha.1: MIT license, Hex metadata, ExDoc (README, demo, changelog), bundled npm licenses in `lib/assets/cell/build/THIRD_PARTY_LICENSES.txt`. The built package was installed from its unpacked files and ran the demo. Not published.

- [x] Running server (`config :kino_isabelle, :server`, with `:sessions` mapping logics to existing session ids). Isabelle sessions belong to the server, not the connection that started them, and outlive it (`server.scala`). Tested against a separate local server and with a session started from `isabelle server -c`. Not tested: a server on another machine (Isabelle binds 127.0.0.1; theory files must be visible under the same path).

### Deviations from the plan, to decide

- [ ] Theory directory: all cells of a runtime share one directory (`$TMP/kino_isabelle_<os pid>`) so that cells can import each other, instead of one directory per cell. Two cells with the same theory name overwrite each other's file.
- [ ] The Check button checks in the cell process and pushes the result to the editor; it does not trigger cell evaluation (the Kino smart-cell API has no call for that). Cell evaluation runs `check/2` itself and reuses the cached result when the text is unchanged.
- [ ] Cache key is `{logic, theory file}` and stores the full source, not a hash.
- [ ] The theory name from the toolbar is not validated; Isabelle reports bad names, but a name like `../x` writes outside the theory directory.
- [ ] Server cleanup needs `/bin/sh`, so Windows is not supported.
