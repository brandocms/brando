defmodule Brando.Blueprint.Forms.Fieldset do
  @moduledoc false
  defstruct label: nil,
            component: nil,
            size: :full,
            align: :start,
            shaded: false,
            style: :regular,
            fields: []
end
