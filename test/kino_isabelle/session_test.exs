defmodule KinoIsabelle.SessionTest do
  use ExUnit.Case

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    tool = Path.join(tmp_dir, "isabelle")
    File.write!(tool, "#!/bin/sh\necho '*** startup failure' >&2\nexit 2\n")
    File.chmod!(tool, 0o755)

    previous = System.get_env("ISABELLE_TOOL")
    restart_session()
    System.put_env("ISABELLE_TOOL", tool)

    on_exit(fn ->
      if previous,
        do: System.put_env("ISABELLE_TOOL", previous),
        else: System.delete_env("ISABELLE_TOOL")

      restart_session()
    end)
  end

  test "reports the output of a server that fails to start" do
    assert KinoIsabelle.check("lemma True by simp") ==
             {:error, {:server_failed, 2, "*** startup failure"}}
  end

  defp restart_session do
    :ok = Supervisor.terminate_child(KinoIsabelle.Application, KinoIsabelle.Session)
    {:ok, _} = Supervisor.restart_child(KinoIsabelle.Application, KinoIsabelle.Session)
  end
end
