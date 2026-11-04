import "./main.css";

import { autocompletion, closeBrackets, completionKeymap } from "@codemirror/autocomplete";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { HighlightStyle, bracketMatching, syntaxHighlighting } from "@codemirror/language";
import { lintGutter, setDiagnostics } from "@codemirror/lint";
import { ChangeSet, EditorState, StateEffect, StateField } from "@codemirror/state";
import { EditorView, drawSelection, highlightActiveLine, keymap, lineNumbers } from "@codemirror/view";
import { tags } from "@lezer/highlight";

import { commandSpan, isabelle } from "./isabelle.js";
import { symbolCompletion, symbolDisplay } from "./symbols.js";

const highlightStyle = HighlightStyle.define([
  { tag: tags.keyword, color: "#0b57d0", fontWeight: "bold" },
  { tag: tags.modifier, color: "#7a3e9d" },
  { tag: tags.string, color: "#1f6f3f" },
  { tag: tags.atom, color: "#1f6f3f" },
  { tag: tags.comment, color: "#8a8a8a", fontStyle: "italic" },
  { tag: tags.number, color: "#a35200" },
  { tag: tags.operator, color: "#7a3e9d" },
]);

// Messages of the last check, mapped through later edits.
const setMessages = StateEffect.define();

const messagesField = StateField.define({
  create: () => null,
  update(messages, tr) {
    for (const effect of tr.effects) if (effect.is(setMessages)) return effect.value;
    if (!messages || !tr.docChanged) return messages;
    return messages.map((m) => ({
      ...m,
      from: tr.changes.mapPos(m.from),
      to: tr.changes.mapPos(m.to),
    }));
  },
});

// Single replacement turning `before` into `after`, to map result positions
// onto text edited since the check started.
function diff(before, after) {
  let prefix = 0;
  const max = Math.min(before.length, after.length);
  while (prefix < max && before[prefix] === after[prefix]) prefix++;
  let suffix = 0;
  while (
    suffix < max - prefix &&
    before[before.length - 1 - suffix] === after[after.length - 1 - suffix]
  ) {
    suffix++;
  }
  return ChangeSet.of(
    [{ from: prefix, to: before.length - suffix, insert: after.slice(prefix, after.length - suffix) }],
    before.length,
  );
}

const template = `
  <div class="isabelle-cell">
    <div class="toolbar">
      <button class="check" type="button">Check</button>
      <label>Session <input name="session" size="12" /></label>
      <label>Header
        <select name="header_mode">
          <option value="auto">generated</option>
          <option value="manual">in text</option>
        </select>
      </label>
      <label class="auto-only">Theory <input name="theory" size="12" /></label>
      <label class="auto-only">Imports <input name="imports" size="24" /></label>
      <label>Assign to <input name="variable" size="10" /></label>
      <span class="status" data-status="idle">idle</span>
    </div>
    <div class="editor"></div>
    <div class="panel"></div>
  </div>
`;

export function init(ctx, { fields, checking, result }) {
  ctx.importCSS("main.css");
  ctx.root.innerHTML = template;

  const root = ctx.root.querySelector(".isabelle-cell");
  const input =(name) => root.querySelector(`[name="${name}"]`);
  const status = root.querySelector(".status");
  const panel = root.querySelector(".panel");
  const button = root.querySelector(".check");

  let syncTimer = null;

  const view = new EditorView({
    parent: root.querySelector(".editor"),
    state: EditorState.create({
      doc: fields.text,
      extensions: [
        lineNumbers(),
        history(),
        drawSelection(),
        highlightActiveLine(),
        bracketMatching(),
        closeBrackets(),
        isabelle,
        syntaxHighlighting(highlightStyle),
        symbolDisplay,
        autocompletion({ override: [symbolCompletion] }),
        lintGutter(),
        messagesField,
        keymap.of([...completionKeymap, ...defaultKeymap, ...historyKeymap, indentWithTab]),
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            clearTimeout(syncTimer);
            syncTimer = setTimeout(sync, 500);
          }
          if (
            update.docChanged ||
            update.selectionSet ||
            update.transactions.some((tr) => tr.effects.some((e) => e.is(setMessages)))
          ) {
            renderPanel(update.state);
          }
        }),
      ],
    }),
  });

  function collect() {
    return {
      text: view.state.doc.toString(),
      variable: input("variable").value.trim(),
      session: input("session").value.trim(),
      theory: input("theory").value.trim(),
      imports: input("imports").value.split(/\s+/).filter((i) => i !== ""),
      header_mode: input("header_mode").value,
    };
  }

  function sync() {
    clearTimeout(syncTimer);
    ctx.pushEvent("update", collect());
  }

  function setStatus(value, title = "") {
    status.dataset.status = value;
    status.textContent = value;
    status.title = title;
    button.disabled = value === "checking";
  }

  function showHeaderMode() {
    root.classList.toggle("manual", input("header_mode").value === "manual");
  }

  function applyResult(result) {
    setStatus(result.status, result.error ?? "");
    const doc = view.state.doc.toString();
    const changes = result.text == null ? null : diff(result.text, doc);
    const map = (pos) => Math.min(changes ? changes.mapPos(pos) : pos, doc.length);
    const messages = result.messages.map((m) => ({ ...m, from: map(m.from), to: map(m.to) }));
    const diagnostics = messages
      .filter((m) => m.kind === "error" || m.kind === "warning")
      .map((m) => ({ from: m.from, to: m.to, severity: m.kind, message: m.text }));
    const lint = setDiagnostics(view.state, diagnostics);
    view.dispatch({ effects: [lint.effects, setMessages.of(messages)].flat() });
  }

  function renderPanel(state) {
    const messages = state.field(messagesField);
    panel.replaceChildren();
    if (!messages) {
      panel.append(note("Press Check to run Isabelle."));
      return;
    }
    const span = commandSpan(state, state.selection.main.head);
    const end = state.doc.length;
    const inSpan = messages.filter(
      (m) => m.from >= span.from && (m.from < span.to || span.to === end),
    );
    if (inSpan.length === 0) {
      panel.append(note("No output for this command."));
      return;
    }
    for (const m of inSpan) {
      const pre = document.createElement("pre");
      pre.className = `message ${m.kind}`;
      pre.textContent = m.text;
      panel.append(pre);
    }
  }

  function note(text) {
    const div = document.createElement("div");
    div.className = "note";
    div.textContent = text;
    return div;
  }

  input("variable").value = fields.variable;
  input("session").value = fields.session;
  input("theory").value = fields.theory;
  input("imports").value = fields.imports.join(" ");
  input("header_mode").value = fields.header_mode;
  showHeaderMode();

  for (const name of ["variable", "session", "theory", "imports", "header_mode"]) {
    input(name).addEventListener("change", () => {
      showHeaderMode();
      sync();
    });
  }

  button.addEventListener("click", () => {
    clearTimeout(syncTimer);
    setStatus("checking");
    ctx.pushEvent("check", collect());
  });

  ctx.handleSync(sync);
  ctx.handleEvent("checking", () => setStatus("checking"));
  ctx.handleEvent("result", applyResult);
  // Sent when the cell rejects the name typed into "Assign to".
  ctx.handleEvent("variable", ({ variable }) => (input("variable").value = variable));

  renderPanel(view.state);
  if (result) applyResult(result);
  if (checking) setStatus("checking");
}
