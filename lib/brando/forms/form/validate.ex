defmodule Brando.Forms.Form.Validate do
  @moduledoc """
  Checks a `Brando.Forms.Form` changeset as a whole: every field key must be
  unique, since a submission stores its values by key.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    # Only a changed field list can introduce a duplicate, and reading it only
    # then avoids loading fields a changeset never touched.
    keys =
      changeset.changes
      |> Map.get(:fields, [])
      |> Enum.reject(&(&1.action in [:replace, :delete]))
      |> Enum.map(&get_field(&1, :key))
      |> Enum.reject(&is_nil/1)

    case keys -- Enum.uniq(keys) do
      [] ->
        changeset

      duplicates ->
        add_error(
          changeset,
          :fields,
          gettext("Two fields share the key %{keys}. Each field needs its own key.",
            keys: duplicates |> Enum.uniq() |> Enum.join(", ")
          )
        )
    end
  end
end
