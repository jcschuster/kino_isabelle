import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { ensureSyntaxTree } from "@codemirror/language";
import { EditorState } from "@codemirror/state";

import { commandSpan, isabelle } from "../js/isabelle.js";

const fixture = (name) => readFileSync(new URL(`../../test/fixtures/${name}`, import.meta.url), "utf8");

function tokens(doc, name) {
  const state = EditorState.create({ doc, extensions: [isabelle] });
  const found = [];
  ensureSyntaxTree(state, doc.length, 5000).iterate({
    enter(node) {
      if (node.name === name) found.push(state.sliceDoc(node.from, node.to));
    },
  });
  return found;
}

// The same fixture is checked against lib/kino_isabelle/syntax.ex.
test("finds the commands of the fixture", () => {
  assert.deepEqual(tokens(fixture("commands.thy"), "command"), JSON.parse(fixture("commands.json")));
});

test("tokenises symbols inside strings and cartouches", () => {
  assert.deepEqual(tokens('lemma "\\<forall>x. P" text ‹\\<alpha>›', "symbol"), ["\\<forall>", "\\<alpha>"]);
});

test("commandSpan runs from a command to the next one", () => {
  const doc = "lemma \"x = x\"\n  by simp\nthm refl";
  const state = EditorState.create({ doc, extensions: [isabelle] });
  const span = (text) => commandSpan(state, doc.indexOf(text));

  assert.deepEqual(span("x ="), { from: 0, to: doc.indexOf("by") });
  assert.deepEqual(span("simp"), { from: doc.indexOf("by"), to: doc.indexOf("thm") });
  assert.deepEqual(span("refl"), { from: doc.indexOf("thm"), to: doc.length });
});
