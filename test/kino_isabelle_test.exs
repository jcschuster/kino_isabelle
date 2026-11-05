defmodule KinoIsabelleTest do
  use ExUnit.Case

  import Kino.Test
  import KinoIsabelle.TestHelpers

  @moduletag :isabelle
  @moduletag timeout: 600_000

  setup :configure_livebook_bridge

  test "maps messages to the cell text" do
    text =
      "lemma \"\\<forall>x. x = (x::nat)\" by simp\n(* 😀 *) lemma \"False\" by simp\nthm conjI\n"

    assert {:ok, result} = KinoIsabelle.check(text, theory: "Mapping")

    assert result.status == :failed
    assert [%{text: "Failed to apply initial proof method" <> _} = error] = errors(result)
    assert slice(text, error) == "by"
    assert Enum.any?(result.messages, &(&1.kind == :writeln and slice(text, &1) == "thm"))
  end

  test "returns the cached result for an unchanged theory" do
    assert {:ok, first} = KinoIsabelle.check("lemma True by simp", theory: "Cached")
    assert {:ok, second} = KinoIsabelle.check("lemma True by simp\n\n", theory: "Cached")

    assert first.status == :ok
    assert second.raw == first.raw
  end

  test "reports header errors at the header" do
    assert {:ok, auto} =
             KinoIsabelle.check("lemma True by simp", theory: "Imp", imports: ["Nope"])

    assert [%{from: 0, to: 0, text: "Cannot load theory file" <> _}] = errors(auto)

    text = "theory Manual imports Nope begin\nend"
    assert {:ok, manual} = KinoIsabelle.check(text, header_mode: :manual)
    assert manual.theory == "Manual"
    assert [error] = errors(manual)
    assert slice(text, error) == "Nope"
  end

  test "fails for an unknown logic session" do
    assert {:error, {:session_start_failed, "NoSuchLogic", [message]}} =
             KinoIsabelle.check("lemma True by simp", session: "NoSuchLogic")

    assert message =~ "Undefined session"
  end

  test "the Check button broadcasts the result to the editor" do
    {kino, _source} = start_smart_cell!(KinoIsabelle.Cell, %{"theory" => "Button"})
    push_event(kino, "check", %{"text" => "lemma \"False\" by simp"})

    assert_broadcast_event(kino, "checking", %{})

    assert_broadcast_event(
      kino,
      "result",
      %{status: :failed, messages: [_ | _] = messages},
      300_000
    )

    assert Enum.any?(messages, &(&1.kind == :error and &1.from == 14))
  end

  test "checks in a session started elsewhere on a configured server" do
    name = "kino_isabelle_test_#{System.unique_integer([:positive])}"
    {:ok, isabelle} = IsabelleClient.Server.executable()

    port =
      Port.open({:spawn_executable, isabelle}, [:binary, args: ["server", "-n", name, "-p", "0"]])

    assert_receive {^port, {:data, data}}, 60_000
    [info] = IsabelleClient.Server.parse_info(data)
    on_exit(fn -> IsabelleClient.Server.kill(name) end)

    {:ok, other} = IsabelleClient.Shared.start_link(port: info.port, password: info.password)
    {:ok, task} = IsabelleClient.Shared.start_session(other, [session: "HOL"], :infinity)
    IsabelleClient.Shared.close(other)

    # "Elsewhere" is no logic: starting a session for it would fail.
    Application.put_env(:kino_isabelle, :server,
      port: info.port,
      password: info.password,
      sessions: %{"Elsewhere" => task.result["session_id"]}
    )

    on_exit(fn ->
      Application.delete_env(:kino_isabelle, :server)
      restart_session()
    end)

    restart_session()
    assert {:ok, %{status: :ok}} = KinoIsabelle.check("lemma True by simp", session: "Elsewhere")

    # The server outlives the runtime's connection.
    restart_session()
    assert {:ok, %{status: :ok}} = KinoIsabelle.check("lemma True by simp", session: "Elsewhere")
  end

  defp errors(result), do: Enum.filter(result.messages, &(&1.kind == :error))
end
