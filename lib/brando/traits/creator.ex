defmodule Brando.Trait.Creator do
  @moduledoc """
  Records who created an entry and who last edited it.

  Adds `creator` (set once, on insert), plus `updated_by` and `edited_at`,
  which stay empty on insert and move only on later user-initiated saves, so
  an entry nobody has edited since creating it reads as created, not edited. `updated_at` is Ecto's and keeps
  meaning "something wrote to this row": block re-rendering, migrations and
  `mix brando.entries.resave` all bump it without going through this trait,
  and saves made as `:system` leave `updated_by`/`edited_at` alone. A save
  whose only changes are `rendered_*` columns does not count as an edit.

  ## Options

    * `:derived` - fields a processing pipeline writes on the user's behalf
      (image sizes, a video's provider status). A save that changes only these,
      and `rendered_*` columns, is not an edit:

          trait :creator, derived: [:sizes, :formats, :status]
  """
  use Brando.Trait

  alias Brando.Trait.Creator.Compiler
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @doc """
  Add creator and last editor to changeset
  """
  @changeset_phase :before_validate_required
  @impl true
  def changeset_mutator(_, _cfg, changeset, :system, _), do: changeset

  # Skip setting creator for existing records that already have a creator and no changes.
  # Matches on %Ecto.Changeset{}.changes directly — this is stable Ecto struct layout.
  def changeset_mutator(_, _cfg, %{data: %{id: id, creator_id: creator_id}, changes: changes} = changeset, _, _)
      when not is_nil(id) and not is_nil(creator_id) and changes == %{} do
    changeset
  end

  def changeset_mutator(_, cfg, changeset, user, _) do
    user_id = user_id(user)

    changeset
    |> put_creator(user_id)
    |> put_editor(user_id, Map.get(cfg, :derived, []))
  end

  defp user_id(%{id: id}), do: id
  defp user_id(id), do: id

  defp put_creator(%{data: %{id: nil}} = changeset, user_id),
    do: Changeset.put_change(changeset, :creator_id, user_id)

  defp put_creator(%{data: %{creator_id: nil}} = changeset, user_id),
    do: Changeset.put_change(changeset, :creator_id, user_id)

  defp put_creator(changeset, _user_id), do: changeset

  defp put_editor(%{data: %{id: nil}} = changeset, _user_id, _derived), do: changeset

  defp put_editor(changeset, user_id, derived) do
    if edited?(changeset, derived), do: stamp_editor(changeset, user_id), else: changeset
  end

  defp stamp_editor(changeset, user_id) do
    changeset
    |> Changeset.put_change(:updated_by_id, user_id)
    |> Changeset.put_change(:edited_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  # A re-render writes only rendered_<field> and rendered_<field>_at, and a
  # processing pipeline only its derived fields; neither is a human edit even
  # when it comes through a user-scoped save.
  defp edited?(%{changes: changes}, derived) do
    Enum.any?(changes, fn {key, _} -> not render_field?(key) and key not in derived end)
  end

  defp render_field?(key), do: key |> Atom.to_string() |> String.starts_with?("rendered_")
end
