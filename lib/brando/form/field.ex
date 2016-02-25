defmodule Brando.Form.Field do
  defstruct form_type: nil,
            name: nil,
            value: nil,
            type: nil,
            errors: nil,
            schema: nil,
            source: nil,
            opts: %{},
            html: nil
end
