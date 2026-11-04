import assert from "node:assert/strict";
import { test } from "node:test";

import { CompletionContext } from "@codemirror/autocomplete";
import { EditorState } from "@codemirror/state";

import { symbolCompletion } from "../js/symbols.js";

function complete(doc, explicit = false) {
  const state = EditorState.create({ doc });
  const result = symbolCompletion(new CompletionContext(state, doc.length, explicit));
  return result && { from: result.from, labels: result.options.map((o) => o.label) };
}

test("completes symbol names after \\ and \\<", () => {
  assert.ok(complete("A \\fora").labels.includes("\\<forall>"));
  assert.equal(complete("A \\<fora").from, 2);
  assert.ok(complete("\\<^su").labels.includes("\\<^sub>"));
});

test("replaces the longest abbreviation", () => {
  assert.deepEqual(complete("A ==>"), { from: 2, labels: ["\\<Longrightarrow>"] });
  assert.deepEqual(complete("A -->"), { from: 2, labels: ["\\<longrightarrow>"] });
});

test("word abbreviations need a word boundary", () => {
  assert.deepEqual(complete("x ALL"), { from: 2, labels: ["\\<forall>"] });
  assert.equal(complete("xALL"), null);
});

test("ignores one-character abbreviations", () => {
  assert.equal(complete("A !"), null);
});
