defmodule Brando.Blueprint.Forms.Input do
  @moduledoc false
  defstruct __spark_metadata__: nil,
            name: nil,
            type: nil,
            component: nil,
            actions: [],
            # The deprecated `ai:` option, as written, for the forms
            # verifier's warning. It runs as an action in `actions`.
            ai: nil,
            opts: []
end
