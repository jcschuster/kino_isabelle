defmodule KinoIsabelle.Result do
  @moduledoc """
  Result of `KinoIsabelle.check/2`. Renders in Livebook as tabs.

    * `:status` - `:ok` when Isabelle accepted the theory, else `:failed`
    * `:theory` - the theory name
    * `:text` - the checked cell text
    * `:messages` - `t:KinoIsabelle.Messages.message/0`s ordered by position;
      `from` and `to` are UTF-16 offsets in `:text`
    * `:node_status` - Isabelle's node status counters, `nil` if the header failed
    * `:raw` - the raw `use_theories` result
  """

  defstruct [:status, :theory, :text, :node_status, :raw, messages: []]

  @type t :: %__MODULE__{
          status: :ok | :failed,
          theory: String.t(),
          text: String.t(),
          messages: [KinoIsabelle.Messages.message()],
          node_status: map() | nil,
          raw: map()
        }
end
