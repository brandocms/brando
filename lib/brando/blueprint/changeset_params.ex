defmodule Brando.Blueprint.ChangesetParams do
  @moduledoc """
  Struct containing parameters for the Blueprint.run_changeset function
  """

  defstruct [
    :module,
    :schema,
    :params,
    :user,
    :sequence,
    :traits,
    :attributes,
    :relations,
    :assets,
    :castable_fields,
    :required_castable_fields,
    :opts
  ]
end
