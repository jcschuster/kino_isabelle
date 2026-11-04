defmodule KinoIsabelle.SyntaxTest do
  use ExUnit.Case, async: true

  alias KinoIsabelle.Syntax

  # The same fixture is checked against assets/js/isabelle.js.
  test "finds the commands of the fixture" do
    text = File.read!("test/fixtures/commands.thy")
    expected = JSON.decode!(File.read!("test/fixtures/commands.json"))

    commands =
      for offset <- Syntax.command_offsets(text),
          do:
            Enum.find(
              expected,
              &String.starts_with?(binary_part(text, offset, byte_size(text) - offset), &1)
            )

    assert commands == expected
  end

  test "skips unterminated comments, strings and cartouches" do
    assert Syntax.command_offsets("lemma (* by") == [0]
    assert Syntax.command_offsets("lemma \"by") == [0]
    assert Syntax.command_offsets("lemma ‹by") == [0]
    assert Syntax.command_offsets("lemma {* by") == [0]
  end

  test "returns byte offsets" do
    assert Syntax.command_offsets("‹∀› lemma") == [10]
  end
end
