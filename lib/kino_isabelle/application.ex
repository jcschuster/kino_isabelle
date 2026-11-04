defmodule KinoIsabelle.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Kino.SmartCell.register(KinoIsabelle.Cell)
    children = [{Task.Supervisor, name: KinoIsabelle.TaskSupervisor}, KinoIsabelle.Session]
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
