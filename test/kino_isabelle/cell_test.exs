defmodule KinoIsabelle.CellTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias KinoIsabelle.Cell

  setup :configure_livebook_bridge

  @texts [
    "lemma True by simp",
    "lemma \"\\<forall>x. x = x\" by simp\n",
    "text ‹\#{not interpolated}›\n\n\tindented\n  \n",
    "text ‹ends with a backslash \\›\nlemma \"a \\\\ b\" \"\"\"",
    "text ‹\n\"\"\"\n›",
    "lemma \"a \\\"\"\" b\"",
    "lemma \"a \\\" b\"\n"
  ]

  for text <- @texts do
    test "generated source evaluates to the text: #{inspect(text)}" do
      text = unquote(text)

      attrs = %{
        "variable" => "result",
        "text" => text,
        "session" => "HOL",
        "theory" => "T",
        "imports" => ["Main", "HOL-Library.Multiset"]
      }

      {source_text, opts} = check_args(Cell.to_source(attrs))

      # A ~S heredoc always ends with a newline; check/2 ignores trailing whitespace.
      assert String.trim_trailing(source_text) == String.trim_trailing(text)
      assert opts == [session: "HOL", theory: "T", imports: ["Main", "HOL-Library.Multiset"]]
    end
  end

  test "manual header mode passes neither theory nor imports" do
    attrs = %{
      "variable" => "result",
      "text" => "theory T imports Main begin\nend",
      "session" => "HOL-Library",
      "header_mode" => "manual"
    }

    assert {_text, [session: "HOL-Library", header_mode: :manual]} =
             check_args(Cell.to_source(attrs))
  end

  test "starts with defaults and keeps editor updates" do
    {kino, source} = start_smart_cell!(Cell, %{"text" => "lemma True by simp"})

    assert {"lemma True by simp\n", [session: "HOL", theory: "Scratch", imports: ["Main"]]} =
             check_args(source)

    assert %{fields: %{"header_mode" => "auto"}, checking: false, result: nil} = connect(kino)

    push_event(kino, "update", %{
      "text" => "thm conjI",
      "imports" => ["Complex_Main"],
      "bogus" => 1
    })

    assert_smart_cell_update(
      kino,
      %{"text" => "thm conjI", "imports" => ["Complex_Main"], "theory" => "Scratch"} = attrs,
      _source
    )

    refute Map.has_key?(attrs, "bogus")
  end

  test "binds the result to the variable" do
    source =
      Cell.to_source(%{
        "variable" => "lists",
        "text" => "",
        "session" => "HOL",
        "header_mode" => "manual"
      })

    assert {:__block__, _, [{:=, _, [{:ok, {:lists, _, nil}}, _call]}, {:lists, _, nil}]} =
             Code.string_to_quoted!(source)
  end

  test "new cells get distinct default variables, saved ones are kept" do
    {first, _source} = start_smart_cell!(Cell, %{})
    {second, _source} = start_smart_cell!(Cell, %{})
    {saved, _source} = start_smart_cell!(Cell, %{"variable" => "basics"})

    variables = Enum.map([first, second, saved], &connect(&1).fields["variable"])

    assert [<<"result", _::binary>>, <<"result", _::binary>>, "basics"] = variables
    assert Enum.uniq(variables) == variables
  end

  for name <- ["", "Foo", "a b", "when", "nil", "_", "_x"] do
    test "rejects the variable #{inspect(name)}" do
      {kino, _source} = start_smart_cell!(Cell, %{"variable" => "basics"})
      push_event(kino, "update", %{"variable" => unquote(name), "theory" => "T"})

      assert_broadcast_event(kino, "variable", %{variable: "basics"})
      assert_smart_cell_update(kino, %{"variable" => "basics", "theory" => "T"}, _source)
    end
  end

  test "accepts the variable \"ok?\"" do
    {kino, _source} = start_smart_cell!(Cell, %{"variable" => "basics"})
    push_event(kino, "update", %{"variable" => "ok?"})

    assert_smart_cell_update(kino, %{"variable" => "ok?"}, source)
    assert source =~ "{:ok, ok?} ="
  end

  test "an evaluated result is sent to the editor and kept for reconnects" do
    {kino, _source} = start_smart_cell!(Cell, %{})
    message = %{kind: :error, text: "Failed", from: 0, to: 5}
    result = %KinoIsabelle.Result{status: :failed, text: "lemma", messages: [message]}

    Cell.scan_eval_result(kino.pid, {:ok, result})

    payload = %{status: :failed, text: "lemma", messages: [message]}
    assert_broadcast_event(kino, "result", ^payload)
    assert %{result: ^payload} = connect(kino)
  end

  defp check_args(source) do
    {:__block__, _, [{:=, _, [_pattern, call]}, _result]} = Code.string_to_quoted!(source)
    {{:., _, [{:__aliases__, _, [:KinoIsabelle]}, :check]}, _, [text, opts]} = call
    {text |> Code.eval_quoted() |> elem(0), opts |> Code.eval_quoted() |> elem(0)}
  end
end
