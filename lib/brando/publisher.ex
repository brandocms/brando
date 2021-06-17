defmodule Brando.Publisher do
  @moduledoc """
  Helpers fpr scheduling and publishing content
  """
  import Ecto.Query
  alias Brando.Users.User
  alias Brando.Worker
  alias Ecto.Changeset

  @type entry :: map()
  @type changeset :: Changeset.t()
  @type user :: User.t()

  @doc """
  Create a job for the publisher worker if we have a publish_at
  field in the entry struct, and it has been changed in changeset
  """
  @spec schedule_publishing(entry, changeset, user) :: {:ok, entry}
  def schedule_publishing(
        %{id: id, publish_at: publish_at, __struct__: schema} = entry,
        %{changes: %{publish_at: _}},
        user
      )
      when not is_nil(publish_at) do
    if DateTime.compare(publish_at, DateTime.utc_now()) == :lt do
      # the publishing date is in the past, just leave it
      {:ok, entry}
    else
      args = %{schema: schema, id: id, user_id: user.id, status: :published}
      entry_identifier = Brando.Schema.identifier_for(entry)

      Brando.repo().delete_all(
        from j in Oban.Job,
          where: fragment("? @> ?", j.args, ^args)
      )

      args
      |> Worker.EntryPublisher.new(
        replace_args: true,
        scheduled_at: publish_at,
        tags: [:publisher, :status],
        meta: %{identifier: entry_identifier}
      )
      |> Oban.insert()

      {:ok, entry}
    end
  end

  def schedule_publishing(entry, _, _) do
    {:ok, entry}
  end

  def schedule_revision(schema, id, revision, publish_at, user) do
    {:ok, publish_at, _} = DateTime.from_iso8601(publish_at)
    args = %{schema: schema, id: id, revision: revision, user_id: user.id}

    {:ok, {revision, {_, decoded_entry}}} = Brando.Revisions.get_revision(schema, id, revision)

    revision_identifier =
      decoded_entry
      |> Brando.Schema.identifier_for()
      |> maybe_add_revision_description(revision)

    args
    |> Worker.EntryPublisher.new(
      replace_args: true,
      scheduled_at: publish_at,
      tags: [:publisher, :revision],
      meta: %{identifier: revision_identifier}
    )
    |> Oban.insert()
  end

  defp maybe_add_revision_description(identifier, %{description: nil}), do: identifier
  defp maybe_add_revision_description(identifier, %{description: ""}), do: identifier

  defp maybe_add_revision_description(identifier, %{description: description}),
    do: Map.update!(identifier, :title, &"#{&1} (#{description})")

  # if we have no publish_at but status = pending -- set status published
  def maybe_override_status(%{changes: %{publish_at: nil}} = changeset) do
    status = Changeset.get_field(changeset, :status)

    if status == :pending do
      Changeset.put_change(changeset, :status, :published)
    else
      changeset
    end
  end

  def maybe_override_status(%{changes: %{publish_at: publish_at}} = changeset)
      when not is_nil(publish_at) do
    status = Changeset.get_field(changeset, :status)

    if DateTime.compare(publish_at, DateTime.utc_now()) == :gt and status == :published do
      Changeset.put_change(changeset, :status, :pending)
    else
      # publish date has passed - if it is still pending, set it to published
      if status == :pending do
        Changeset.put_change(changeset, :status, :published)
      else
        changeset
      end
    end
  end

  def maybe_override_status(changeset) do
    changeset
  end

  def list_jobs do
    query =
      from j in Oban.Job,
        where: "publisher" in j.tags,
        order_by: j.scheduled_at

    {:ok, Brando.repo().all(query)}
  end

  def delete_job(id) do
    Brando.repo().delete_all(from j in Oban.Job, where: j.id == ^id)
  end
end
