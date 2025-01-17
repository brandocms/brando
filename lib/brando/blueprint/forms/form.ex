defmodule Brando.Blueprint.Forms.Form do
  @moduledoc false
  defstruct name: :default,
            __identifier__: nil,
            query: nil,
            after_save: nil,
            default_params: %{},
            tabs: [],
            blocks: [],
            transformers: [],
            redirect_on_save: nil
end
