defmodule Brando.Form.Field do
  @moduledoc """
  Struct definition for a form field.
  """
  defstruct form_type: nil,
            name: nil,
            value: nil,
            type: nil,
            errors: nil,
            schema: nil,
            source: nil,
            opts: %{},
            html: []
end
