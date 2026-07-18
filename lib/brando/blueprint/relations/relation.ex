defmodule Brando.Blueprint.Relations.Relation do
  @moduledoc false

  @type t :: %__MODULE__{
          __identifier__: term(),
          __spark_metadata__: term(),
          name: atom() | nil,
          type: atom() | nil,
          opts: map() | nil
        }

  defstruct __identifier__: nil,
            __spark_metadata__: nil,
            name: nil,
            type: nil,
            opts: nil
end
