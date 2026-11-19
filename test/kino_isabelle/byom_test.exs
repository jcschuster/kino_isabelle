defmodule KinoIsabelle.ByomTest do
  use ExUnit.Case

  @moduletag :byom
  @moduletag timeout: 600_000

  setup do
    KinoIsabelle.use_server(
      url: System.fetch_env!("ISABELLE_BYOM_URL"),
      password: System.fetch_env!("ISABELLE_BYOM_PASSWORD")
    )

    on_exit(fn -> KinoIsabelle.use_server(:local) end)
  end

  test "uploads theories, which can import each other" do
    assert {:ok, %{status: :ok}} =
             KinoIsabelle.check(~S|definition "one = (1::nat)"|, theory: "Byom_A")

    assert {:ok, %{status: :ok}} =
             KinoIsabelle.check(~S|lemma "one = 1" by (simp add: one_def)|,
               theory: "Byom_B",
               imports: ["Byom_A"]
             )

    assert {:ok, %{status: :failed}} =
             KinoIsabelle.check(~S|lemma "one = 2" by (simp add: one_def)|,
               theory: "Byom_C",
               imports: ["Byom_A"]
             )
  end
end
