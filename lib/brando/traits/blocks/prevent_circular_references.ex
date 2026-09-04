defmodule Brando.Trait.Blocks.PreventCircularReferences do
  @moduledoc """
  Ensure that the fragment is not referencing itself.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  alias Ecto.Changeset

  def changeset_mutator(_module, _config, %{changes: %{data: data}} = changeset, _user, _) do
    json = inspect(data)

    # we need the keys
    key = Changeset.get_field(changeset, :key)
    parent_key = Changeset.get_field(changeset, :parent_key)
    language = Changeset.get_field(changeset, :language)

    # build a fragment ref string
    ref_string = "{% fragment #{parent_key} #{key} #{language} %}"

    if String.contains?(json, ref_string) do
      error_msg =
        gettext("Fragment contains circular reference to itself, %{ref_string}",
          ref_string: ref_string
        )

      Changeset.add_error(
        changeset,
        :data,
        error_msg
      )
    else
      changeset
    end
  end

  def changeset_mutator(_module, _config, changeset, _user, _) do
    changeset
  end
end
