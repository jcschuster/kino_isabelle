defmodule KinoIsabelle.SessionTest do
  use ExUnit.Case

  alias KinoIsabelle.Session

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    tool = Path.join(tmp_dir, "isabelle")
    File.write!(tool, "#!/bin/sh\necho '*** startup failure' >&2\nexit 2\n")
    File.chmod!(tool, 0o755)

    previous = System.get_env("ISABELLE_TOOL")
    Session.restart()
    System.put_env("ISABELLE_TOOL", tool)

    on_exit(fn ->
      if previous,
        do: System.put_env("ISABELLE_TOOL", previous),
        else: System.delete_env("ISABELLE_TOOL")

      Application.delete_env(:kino_isabelle, :server)
      Session.restart()
    end)
  end

  test "reports the output of a server that fails to start" do
    assert KinoIsabelle.check("lemma True by simp") ==
             {:error, {:server_failed, 2, "*** startup failure"}}
  end

  test "use_server restarts the session only for a changed setting" do
    pid = Process.whereis(Session)
    assert KinoIsabelle.use_server(:local) == :ok
    assert Process.whereis(Session) == pid

    assert KinoIsabelle.use_server(port: 4711, password: "secret") == :ok
    assert Application.get_env(:kino_isabelle, :server) == [port: 4711, password: "secret"]
    refute Process.whereis(Session) == pid
  end

  test "use_server(:local) starts a server of the runtime's own" do
    KinoIsabelle.use_server(port: 4711, password: "secret")
    KinoIsabelle.use_server(:local)

    assert KinoIsabelle.check("lemma True by simp") ==
             {:error, {:server_failed, 2, "*** startup failure"}}
  end

  test "reports a configured URL the client cannot use" do
    KinoIsabelle.use_server(url: "ftp://isabelle.example", password: "secret")

    assert KinoIsabelle.check("lemma True by simp") ==
             {:error, {:connect_failed, :expected_loopback_or_https_url}}
  end

  test "rejects a configured server without password" do
    Application.put_env(:kino_isabelle, :server, port: 4711)
    assert KinoIsabelle.check("lemma True by simp") == {:error, :bad_server_config}
  end

  test "reports a configured server that cannot be reached" do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)

    Application.put_env(:kino_isabelle, :server, port: port, password: "secret")

    assert KinoIsabelle.check("lemma True by simp") ==
             {:error, {:connect_failed, :econnrefused}}
  end
end
