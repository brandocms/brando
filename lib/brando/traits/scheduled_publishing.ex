defmodule Brando.Trait.ScheduledPublishing do
  @moduledoc """
  Adds `publish_at` and `unpublish_at`.

  An entry that is published without a `publish_at` gets the time it was
  written. This runs when the changeset is written (`prepare_changes/2`), so it
  applies to every save — the admin form, context mutations, revisions and
  jobs — and not to form validation, which never writes.

  `unpublish_at` is when the entry expires: `Brando.Publisher` schedules a job
  that deactivates it then, the same status change as deactivating it by hand.
  It has to come after `publish_at`; clearing it cancels the job. Publishing
  the entry again after it expired clears the expiry that has passed.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  alias Brando.Trait.ScheduledPublishing.Compiler

  import Ecto.Changeset

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @impl true
  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    changeset
    |> clear_passed_unpublish_at()
    |> validate_unpublish_at()
    |> prepare_changes(&stamp_publish_at/1)
  end

  # Publishing an entry again after it expired: the expiry that ended it is
  # over, and kept it would show as planned and fail the next save that
  # touches a date. A new expiry set in the same change is kept.
  defp clear_passed_unpublish_at(%{changes: %{status: status} = changes} = changeset)
       when status in [:published, :pending] and not is_map_key(changes, :unpublish_at) do
    case get_field(changeset, :unpublish_at) do
      %DateTime{} = unpublish_at ->
        if DateTime.after?(unpublish_at, DateTime.utc_now()),
          do: changeset,
          else: put_change(changeset, :unpublish_at, nil)

      _ ->
        changeset
    end
  end

  defp clear_passed_unpublish_at(changeset), do: changeset

  # Status changed to :published, but no publish_at set = set to utc_now
  @doc false
  def stamp_publish_at(%{changes: %{status: :published}} = changeset) do
    if get_field(changeset, :publish_at) == nil do
      put_change(changeset, :publish_at, DateTime.truncate(DateTime.utc_now(), :second))
    else
      changeset
    end
  end

  def stamp_publish_at(changeset), do: changeset

  # Checked when either date changes, so an entry saved for something else is
  # never held back by dates it already had.
  defp validate_unpublish_at(%{changes: changes} = changeset)
       when is_map_key(changes, :unpublish_at) or is_map_key(changes, :publish_at) do
    with %DateTime{} = unpublish_at <- get_field(changeset, :unpublish_at),
         %DateTime{} = publish_at <- get_field(changeset, :publish_at),
         false <- DateTime.after?(unpublish_at, publish_at) do
      add_error(changeset, :unpublish_at, gettext("Must be after the publishing date"))
    else
      _ -> changeset
    end
  end

  defp validate_unpublish_at(changeset), do: changeset
end
