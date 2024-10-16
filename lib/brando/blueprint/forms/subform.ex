defmodule Brando.Blueprint.Forms.Subform do
  defstruct name: nil,
            label: nil,
            instructions: nil,
            cardinality: :one,
            sub_fields: [],
            style: :regular,
            default: nil,
            listing: nil,
            component: nil
end
