defmodule KinoIsabelle.PositionsTest do
  use ExUnit.Case, async: true

  import KinoIsabelle.TestHelpers

  alias KinoIsabelle.{Positions, Theory}

  # Raw positions of the error on "by" as reported by Isabelle2025-2 for each
  # text, checked in auto header mode under the given theory name.
  @observed [
    {"Pos_plain", "lemma \"False\" by simp\n", 53, 55},
    {"Pos_emoji", "(* 😀😀 *) lemma \"False\" by simp\n", 62, 64},
    {"Pos_combining", "(* éé *) lemma \"False\" by simp\n", 68, 70},
    {"Pos_cjk", "(* 漢字 *) lemma \"False\" by simp\n", 60, 62},
    {"Pos_fraktur", "(* 𝔄𝔄 *) lemma \"False\" by simp\n", 64, 66},
    {"Pos_named", "(* \\<foo> \\<^sub> \\<forall> *) lemma \"False\" by simp\n", 65, 67},
    {"Pos_crlf", "(* a *)\r\n\r\nlemma \"False\" by simp\r\n", 61, 63},
    {"Pos_cr", "(* a *)\r\rlemma \"False\" by simp\n", 59, 61},
    {"Pos_tab_ff", "(*\t\f*) lemma \"False\" by simp\n", 61, 63},
    {"Pos_mal_str", "lemma \"\\<abc = x\" by simp\n", 55, 57}
  ]

  for {name, text, offset, end_offset} <- @observed do
    test "maps Isabelle's offsets for #{name}" do
      {:ok, theory} = Theory.new(unquote(text), theory: unquote(name))
      table = Positions.new(theory.text, theory.header_symbols)

      range =
        Positions.range(table, %{"offset" => unquote(offset), "end_offset" => unquote(end_offset)})

      assert slice(unquote(text), range) == "by"
    end
  end

  test "a missing or empty end_offset covers one symbol" do
    table = Positions.new("\\<forall>x", 0)

    assert Positions.range(table, %{"offset" => 1}) == {0, 9}
    assert Positions.range(table, %{"offset" => 1, "end_offset" => 1}) == {0, 9}
    assert Positions.range(table, %{"offset" => 2, "end_offset" => 2}) == {9, 10}
  end

  test "header positions map to the start, positions past the text to its end" do
    table = Positions.new("ab", 10)

    assert Positions.range(table, %{"offset" => 3, "end_offset" => 8}) == {0, 0}
    assert Positions.range(table, %{"offset" => 11, "end_offset" => 12}) == {0, 1}
    assert Positions.range(table, %{"offset" => 15, "end_offset" => 18}) == {2, 2}
  end

  test "a message without position maps to the start" do
    assert Positions.range(Positions.new("ab", 0), nil) == {0, 0}
  end

  test "counts symbols like Isabelle" do
    assert Positions.symbol_count("a\\<forall>\\<^sub>😀\r\n\\<abc\\<") == 7
  end

  test "converts byte offsets to UTF-16 offsets" do
    assert Positions.utf16_offset("😀∀a", 7) == 3
  end
end
