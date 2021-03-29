defmodule Brando.Trait.Villain.CircularReferencesGuard do
  @moduledoc """
  Ensure that the fragment is not referencing itself.
  """
  use Brando.Trait
  import Brando.Gettext

  def changeset_mutator(_module, _config, changeset, _user) do
    case Ecto.Changeset.get_change(changeset, :data) do
      nil ->
        changeset

      change ->
        json = Jason.encode!(change)

        # we need the keys
        key = Ecto.Changeset.get_field(changeset, :key)
        parent_key = Ecto.Changeset.get_field(changeset, :parent_key)
        language = Ecto.Changeset.get_field(changeset, :language)

        # build a fragment ref string
        ref_string = "{% fragment #{parent_key} #{key} #{language} %}"

        if String.contains?(json, ref_string) do
          error_msg =
            gettext("Fragment contains circular reference to itself, %{ref_string}",
              ref_string: ref_string
            )

          Ecto.Changeset.add_error(
            changeset,
            :data,
            error_msg
          )
        else
          changeset
        end
    end
  end
end
