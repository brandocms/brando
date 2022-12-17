defmodule Brando.Blueprint.Form.Subform do
  defstruct field: nil,
            label: nil,
            cardinality: :one,
            sub_fields: [],
            style: :regular,
            default: nil,
            listing: nil,
            component: nil
end
