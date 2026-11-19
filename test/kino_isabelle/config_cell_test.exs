defmodule KinoIsabelle.ConfigCellTest do
  use ExUnit.Case, async: true

  import Kino.Test

  alias KinoIsabelle.ConfigCell

  setup :configure_livebook_bridge

  test "starts with a local server" do
    {kino, source} = start_smart_cell!(ConfigCell, %{})

    assert source == "KinoIsabelle.use_server(:local)"
    assert %{"server" => "local", "port" => nil, "sessions" => %{}} = connect(kino)
  end

  test "a running server reads the password from a Livebook secret" do
    {kino, _source} = start_smart_cell!(ConfigCell, %{})

    push_event(kino, "update", %{
      "server" => "host",
      "host" => "",
      "port" => 4711,
      "password_secret" => "ISABELLE",
      "sessions" => [["HOL", "1234"]]
    })

    assert_smart_cell_update(kino, %{"sessions" => %{"HOL" => "1234"}}, source)

    assert Code.string_to_quoted!(source) ==
             Code.string_to_quoted!("""
             KinoIsabelle.use_server(
               port: 4711,
               password: System.fetch_env!("LB_ISABELLE"),
               sessions: %{"HOL" => "1234"}
             )
             """)
  end

  test "the source of a running server keeps a given host and drops a missing password" do
    attrs = %{
      "server" => "host",
      "host" => "isabelle.local",
      "port" => 4711,
      "password_secret" => "",
      "sessions" => %{}
    }

    assert ConfigCell.to_source(attrs) ==
             ~s|KinoIsabelle.use_server(host: "isabelle.local", port: 4711)|
  end

  test "a URL replaces host and port" do
    attrs = %{
      "server" => "url",
      "url" => "wss://byom.example/isabelle",
      "host" => "ignored",
      "port" => 4711,
      "password_secret" => "BYOM",
      "sessions" => %{}
    }

    assert ConfigCell.to_source(attrs) == """
           KinoIsabelle.use_server(
             url: "wss://byom.example/isabelle",
             password: System.fetch_env!("LB_BYOM")
           )\
           """
  end

  for {key, value} <- [
        {"server", "running"},
        {"port", 70_000},
        {"port", "4711"},
        {"password_secret", "LB-X"},
        {"sessions", [["HOL"]]},
        {"sessions", [["", "1234"]]}
      ] do
    test "rejects #{key} #{inspect(value)} and resets the client" do
      {kino, _source} = start_smart_cell!(ConfigCell, %{"server" => "host", "port" => 4711})
      push_event(kino, "update", %{unquote(key) => unquote(value), "host" => "h"})

      assert_broadcast_event(kino, "fields", %{
        "server" => "host",
        "port" => 4711,
        "host" => "h"
      })

      assert_smart_cell_update(kino, %{"server" => "host", "port" => 4711, "host" => "h"}, _)
    end
  end
end
