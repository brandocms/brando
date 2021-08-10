defmodule Brando.Blueprint.Form.Subform do
  defstruct field: nil,
            cardinality: :one,
            sub_fields: [],
            style: :regular,
            default: nil,
            component: nil
end
