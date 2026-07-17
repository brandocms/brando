defmodule Brando.Blueprint.Forms.Subform do
  @moduledoc false
  defstruct __spark_metadata__: nil,
            name: nil,
            label: nil,
            instructions: nil,
            cardinality: :one,
            sub_fields: [],
            style: :regular,
            default: nil,
            listing: nil,
            component: nil
end
