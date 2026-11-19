# Changelog

## Unreleased

- "Isabelle server" smart cell: starts a local server or connects to a running one by host and port or by URL, with the password read from a Livebook secret.
- `config :kino_isabelle, :server` takes `:url` instead of `:host` and `:port` for an [Isabelle BYOM](https://github.com/davfuenmayor/isabelle-byom) server (`wss://…`); theories are uploaded to it.
- `KinoIsabelle.use_server/1` sets the server; a changed setting also applies after the first check.
- `config :kino_isabelle, :server` also takes `:local`.

## 0.1.0-alpha.2

- `config :kino_isabelle, :server` connects the runtime to a running Isabelle server instead of starting one; `:sessions` reuses logic sessions already running there.

## 0.1.0-alpha.1

First pre-release.

- "Isabelle theory" smart cell: CodeMirror editor with outer-syntax highlighting, symbol display and symbol completion; Check button; errors and warnings as lint diagnostics; panel with the messages of the command under the cursor.
- The cell binds its result to a variable set in the toolbar ("Assign to").
- `KinoIsabelle.check/2`, returning a `KinoIsabelle.Result` that renders as Summary / Messages / Errors / Raw tabs.
- One Isabelle server per runtime, started on the first check and stopped with the runtime.
