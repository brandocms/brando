defmodule Brando.Blueprint.ChangesetParams do
  @moduledoc """
  Struct containing parameters for the Blueprint.run_changeset function
  """

  @type t :: %__MODULE__{
          module: module(),
          schema: struct(),
          params: map(),
          user: term(),
          sequence: integer() | nil,
          traits_before_validate_required: list(),
          traits_after_validate_required: list(),
          attributes: list(),
          relations: list(),
          assets: list(),
          castable_fields: [atom()],
          required_castable_fields: [atom()],
          opts: keyword()
        }

  defstruct [
    :module,
    :schema,
    :params,
    :user,
    :sequence,
    :traits_before_validate_required,
    :traits_after_validate_required,
    :attributes,
    :relations,
    :assets,
    :castable_fields,
    :required_castable_fields,
    :opts
  ]
end
