// Isabelle symbols: \<name> is displayed as its Unicode glyph, and typed as
// \name, \<name or an abbreviation such as ==>.

import { Decoration, EditorView, MatchDecorator, ViewPlugin, WidgetType } from "@codemirror/view";
import table from "../../priv/symbols.json";

export const symbols = table.map(([name, code, abbrevs]) => ({
  name,
  glyph: String.fromCodePoint(code),
  abbrevs,
}));

const glyphs = new Map(symbols.map((s) => [s.name, s.glyph]));

class SymbolWidget extends WidgetType {
  constructor(glyph) {
    super();
    this.glyph = glyph;
  }

  eq(other) {
    return other.glyph === this.glyph;
  }

  toDOM() {
    const span = document.createElement("span");
    span.className = "cm-isabelle-symbol";
    span.textContent = this.glyph;
    return span;
  }

  ignoreEvent() {
    return false;
  }
}

const decorator = new MatchDecorator({
  regexp: /\\<\^?[A-Za-z][A-Za-z0-9_']*>/g,
  decoration: (match) => {
    const glyph = glyphs.get(match[0]);
    return glyph ? Decoration.replace({ widget: new SymbolWidget(glyph) }) : null;
  },
});

export const symbolDisplay = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = decorator.createDeco(view);
    }

    update(update) {
      this.decorations = decorator.updateDeco(update, this.decorations);
    }
  },
  {
    decorations: (plugin) => plugin.decorations,
    provide: (plugin) =>
      EditorView.atomicRanges.of((view) => view.plugin(plugin)?.decorations ?? Decoration.none),
  },
);

const option = (symbol) => ({ label: symbol.name, detail: symbol.glyph, apply: symbol.name });

// Abbreviations of one character (!, ?, …) would fire on ordinary input.
const abbrevs = symbols.flatMap((s) =>
  s.abbrevs.filter((a) => a.length > 1).map((abbrev) => ({ abbrev, symbol: s })),
);

export function symbolCompletion(context) {
  const named = context.matchBefore(/\\<?\^?[A-Za-z0-9_']*/);
  if (named && (named.text.length > 1 || context.explicit)) {
    const prefix = named.text.replace(/^\\<?/, "");
    return {
      from: named.from,
      options: symbols.filter((s) => s.name.slice(2).startsWith(prefix)).map(option),
      filter: false,
    };
  }

  const before = context.state.sliceDoc(Math.max(0, context.pos - 8), context.pos);
  const matches = abbrevs.filter(
    ({ abbrev }) =>
      before.endsWith(abbrev) &&
      !(/^\w/.test(abbrev) && /\w/.test(before.charAt(before.length - abbrev.length - 1))),
  );
  if (matches.length === 0) return null;

  const length = Math.max(...matches.map(({ abbrev }) => abbrev.length));
  return {
    from: context.pos - length,
    options: matches.filter(({ abbrev }) => abbrev.length === length).map(({ symbol }) => option(symbol)),
    filter: false,
  };
}
