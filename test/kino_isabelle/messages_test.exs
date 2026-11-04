defmodule KinoIsabelle.MessagesTest do
  use ExUnit.Case, async: true

  alias KinoIsabelle.{Messages, Positions, Theory}

  describe "normalize/3 for a use_theories result" do
    setup do
      text = "lemma \"False\" by simp\nthm conjI\n"
      {:ok, theory} = Theory.new(text, theory: "N")
      %{theory: theory, table: Positions.new(text, theory.header_symbols), path: theory.path}
    end

    test "keeps own messages and foreign errors, ordered by position", ctx do
      by = pos(ctx, 15, 17)
      thm = pos(ctx, 23, 26)

      result = %{
        "errors" => [
          %{"kind" => "error", "message" => "Failed", "pos" => by},
          %{
            "kind" => "error",
            "message" => "Other.thy broken",
            "pos" => %{"file" => "/x/Other.thy", "offset" => 3}
          }
        ],
        "nodes" => [
          %{
            "node_name" => ctx.path,
            "messages" => [
              %{"kind" => "writeln", "message" => "?P ⟹ ?Q ⟹ ?P ∧ ?Q", "pos" => thm},
              %{"kind" => "error", "message" => "Failed", "pos" => by},
              %{"kind" => "legacy", "message" => "Legacy feature", "pos" => by}
            ]
          },
          %{
            "node_name" => "/x/Other.thy",
            "messages" => [%{"kind" => "writeln", "message" => "skip"}]
          }
        ]
      }

      assert Messages.normalize(result, ctx.theory, ctx.table) == [
               %{kind: :error, text: "Other.thy broken", from: 0, to: 0},
               %{kind: :error, text: "Failed", from: 14, to: 16},
               %{kind: :warning, text: "Legacy feature", from: 14, to: 16},
               %{kind: :writeln, text: "?P ⟹ ?Q ⟹ ?P ∧ ?Q", from: 22, to: 25}
             ]
    end

    defp pos(ctx, from, to) do
      header = ctx.theory.header_symbols
      %{"file" => ctx.path, "offset" => header + from, "end_offset" => header + to}
    end
  end

  describe "normalize/3 for a failed task" do
    test "decodes the YXML message and its position" do
      text = "theory D imports Nonexistent begin\nend"
      {:ok, theory} = Theory.new(text, header_mode: :manual)
      file = theory.path

      message =
        "Cannot load theory file \"/t/Nonexistent.thy\"\n" <>
          "\x05\x06position\x06line=1\x06offset=18\x06end_offset=29\x06file=#{file}\x05" <>
          " (line 1)\x05\x06\x05" <>
          "\x05\x06report\x05\x05\x06completion\x05\x05\x06:\x05theory\x05\x06\x05\x05\x06\x05\x05\x06\x05" <>
          "\nThe error(s) above occurred"

      assert [msg] =
               Messages.normalize(
                 %{"kind" => "error", "message" => message},
                 theory,
                 Positions.new(text, 0)
               )

      assert msg == %{
               kind: :error,
               text:
                 "Cannot load theory file \"/t/Nonexistent.thy\"\n (line 1)\nThe error(s) above occurred",
               from: 17,
               to: 28
             }
    end

    test "ignores positions in other files" do
      {:ok, theory} = Theory.new("theory D imports Main begin\nend", header_mode: :manual)
      message = "Bad\x05\x06position\x06offset=3\x06file=/x/Other.thy\x05\x05\x06\x05"

      assert [%{text: "Bad", from: 0, to: 0}] =
               Messages.normalize(
                 %{"kind" => "error", "message" => message},
                 theory,
                 Positions.new("", 0)
               )
    end
  end

  describe "bucket/2" do
    test "groups messages by the command span they start in" do
      text = "(* c *)\nlemma \"∀x. x\"\n  by simp\nthm conjI\n"
      by = Positions.utf16_offset(text, :binary.match(text, "by") |> elem(0))
      thm = Positions.utf16_offset(text, :binary.match(text, "thm") |> elem(0))

      messages = [
        %{kind: :error, text: "foreign", from: 0, to: 0},
        %{kind: :error, text: "failed", from: by, to: by + 2},
        %{kind: :writeln, text: "theorem", from: thm, to: thm + 3},
        %{kind: :writeln, text: "at end", from: String.length(text), to: String.length(text)}
      ]

      assert [
               %{line: 1, command: "(* c *)", messages: [%{text: "foreign"}]},
               %{line: 3, command: "by simp", messages: [%{text: "failed"}]},
               %{line: 4, command: "thm conjI", messages: [%{text: "theorem"}, %{text: "at end"}]}
             ] = Messages.bucket(messages, text)
    end

    test "a text starting with a command has no separate leading span" do
      assert [%{from: 0, line: 1, command: "lemma True by simp"}] =
               Messages.bucket(
                 [%{kind: :writeln, text: "t", from: 0, to: 5}],
                 "lemma True by simp"
               )
    end
  end
end
