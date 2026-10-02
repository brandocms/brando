defmodule BrandoAdmin.Components.Activity.Comparison do
  @moduledoc """
  What changed between two revisions of an entry, for the activity log's
  Compare: the same field and block sections a recovery copy's preview
  shows, with the older revision in place of the saved entry.
  """
  import Ecto.Query

  alias Brando.Revisions
  alias Brando.Revisions.Revision
  alias BrandoAdmin.Components.Form.DraftPreview
  alias BrandoAdmin.Components.Form.Drafts

  @doc """
  The revisions an event compares, `{from, to}`: the revision it replaced
  when it restored one, else the latest revision before it. `nil` when the
  event saved no revision or nothing came before it.
  """
  def revisions(%{revision: nil}), do: nil

  def revisions(%{action: :revision_restored, details: %{"replaced" => replaced}, revision: revision})
      when replaced != revision,
      do: {replaced, revision}

  def revisions(%{revision: 0}), do: nil
  def revisions(%{revision: revision}) when is_integer(revision), do: {revision - 1, revision}
  def revisions(_), do: nil

  @doc """
  Compare revision `from` with revision `to` of entry `entry_id`. Uses the
  latest revision before `from` that is still kept when `from` was purged.
  Returns `{:ok, %{from: from, to: to, sections: sections}}` or `:error` when
  either side is gone.
  """
  def build(schema, entry_id, from, to, user) do
    from = kept_at_or_before(schema, entry_id, from)

    with true <- is_integer(from),
         blueprint when not is_nil(blueprint) <- schema.__form__(:default),
         {:ok, {_, {_, before}}} <- Revisions.get_revision(schema, entry_id, from),
         {:ok, {_, {_, after_entry}}} <- Revisions.get_revision(schema, entry_id, to) do
      sections =
        DraftPreview.comparisons(
          Drafts.saved_payload(schema, blueprint, before, user),
          Drafts.saved_payload(schema, blueprint, after_entry, user),
          schema: schema,
          blueprint: blueprint
        )

      {:ok, %{from: from, to: to, sections: sections}}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp kept_at_or_before(schema, entry_id, revision) do
    from(r in Revision,
      where: r.entry_type == ^to_string(schema) and r.entry_id == ^entry_id and r.revision <= ^revision,
      select: max(r.revision)
    )
    |> Brando.Repo.one()
  end
end
