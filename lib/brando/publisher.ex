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
    args = %{schema: schema, id: id, user_id: user.id, status: :published}

    Brando.repo().delete_all(
      from j in Oban.Job,
        where: fragment("? @> ?", j.args, ^args)
    )

    args
    |> Worker.Publisher.new(
      replace_args: true,
      scheduled_at: publish_at,
      tags: [:publisher, :status]
    )
    |> Oban.insert()

    {:ok, entry}
  end

  def schedule_publishing(entry, _, _) do
    {:ok, entry}
  end

  def schedule_revision(schema, id, revision, publish_at, user) do
    {:ok, publish_at, _} = DateTime.from_iso8601(publish_at)
    args = %{schema: schema, id: id, revision: revision, user_id: user.id}

    args
    |> Worker.Publisher.new(
      replace_args: true,
      scheduled_at: publish_at,
      tags: [:publisher, :revision]
    )
    |> Oban.insert()
  end

  def maybe_override_status(%{changes: %{publish_at: publish_at}} = changeset)
      when not is_nil(publish_at) do
    status = Changeset.get_field(changeset, :status)

    if DateTime.compare(publish_at, DateTime.utc_now()) == :gt and status == :published do
      Changeset.put_change(changeset, :status, :pending)
    else
      changeset
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
end
