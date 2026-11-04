// Outer syntax of Isabelle theories. Command detection must agree with
// lib/kino_isabelle/syntax.ex, which buckets messages on the Elixir side.

import { StreamLanguage, ensureSyntaxTree, syntaxTree } from "@codemirror/language";
import { tags } from "@lezer/highlight";
import keywords from "../../priv/keywords.json";

const commands = new Set(Object.keys(keywords.major));
const minor = new Set(keywords.minor);
const symbolic = [...commands, ...minor]
  .filter((k) => !/^[A-Za-z]/.test(k))
  .sort((a, b) => b.length - a.length);

const ident = /^[A-Za-z][A-Za-z0-9_']*(?:\.[A-Za-z][A-Za-z0-9_']*)*/;
const number = /^[0-9]+(?:\.[0-9]+)?/;
const symbol = /^\\<\^?[A-Za-z][A-Za-z0-9_']*>/;
const open = /^(?:\\<open>|‹)/;
const close = /^(?:\\<close>|›)/;

function keywordToken(word) {
  return commands.has(word) ? "command" : minor.has(word) ? "minor" : null;
}

function comment(stream, state) {
  while (!stream.eol()) {
    if (stream.match("(*")) state.comment++;
    else if (stream.match("*)")) {
      if (--state.comment === 0) break;
    } else stream.next();
  }
  return "comment";
}

function verbatim(stream, state) {
  if (stream.skipTo("*}")) {
    stream.match("*}");
    state.verbatim = false;
  } else stream.skipToEnd();
  return "string";
}

// Inner syntax: only strings and the symbols inside them.
function quoted(stream, state) {
  if (stream.match(symbol)) return "symbol";
  while (!stream.eol()) {
    if (stream.match(symbol, false)) break;
    const ch = stream.next();
    if (ch === "\\") stream.next();
    else if (ch === state.quote) {
      state.quote = null;
      break;
    }
  }
  return "string";
}

function cartouche(stream, state) {
  if (!stream.match(open, false) && !stream.match(close, false) && stream.match(symbol)) {
    return "symbol";
  }
  while (!stream.eol()) {
    if (stream.match(open)) state.cartouche++;
    else if (stream.match(close)) {
      if (--state.cartouche === 0) break;
    } else if (stream.match(symbol, false)) break;
    else stream.next();
  }
  return "string";
}

export const isabelle = StreamLanguage.define({
  name: "isabelle",
  startState: () => ({ comment: 0, quote: null, cartouche: 0, verbatim: false }),
  copyState: (state) => ({ ...state }),
  token(stream, state) {
    if (state.comment) return comment(stream, state);
    if (state.verbatim) return verbatim(stream, state);
    if (state.quote) return quoted(stream, state);
    if (state.cartouche) return cartouche(stream, state);
    if (stream.eatSpace()) return null;

    if (stream.match("(*")) {
      state.comment = 1;
      return comment(stream, state);
    }
    if (stream.match("{*")) {
      state.verbatim = true;
      return verbatim(stream, state);
    }
    if (stream.eat('"') || stream.eat("`")) {
      state.quote = stream.current();
      return "string";
    }
    if (stream.match(open)) {
      state.cartouche = 1;
      return "string";
    }

    let m;
    if ((m = stream.match(ident))) return keywordToken(m[0]);
    if (stream.match(number)) return "number";
    if ((m = stream.match(symbol))) {
      if (m[0] === "\\<comment>") return "comment";
      return keywordToken(m[0]) ?? "symbol";
    }
    for (const k of symbolic) {
      if (stream.match(k)) return commands.has(k) ? "command" : "operator";
    }
    stream.next();
    return null;
  },
  tokenTable: { command: tags.keyword, minor: tags.modifier, symbol: tags.atom },
  languageData: { commentTokens: { block: { open: "(*", close: "*)" } } },
});

// The command span containing `pos`: from its command keyword to the next one.
export function commandSpan(state, pos) {
  const tree = ensureSyntaxTree(state, state.doc.length, 200) ?? syntaxTree(state);
  let from = 0;
  let to = state.doc.length;
  tree.iterate({
    enter(node) {
      if (node.name !== "command") return;
      if (node.from <= pos) from = node.from;
      else if (node.from < to) to = node.from;
    },
  });
  return { from, to };
}
