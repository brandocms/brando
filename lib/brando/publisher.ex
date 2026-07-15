defmodule Brando.Publisher do
  @moduledoc """
  Helpers for scheduling and publishing content.
  """
  import Ecto.Query

  alias Brando.Blueprint.Identifier
  alias Brando.Repo
  alias Brando.Revisions
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
    if DateTime.before?(publish_at, DateTime.utc_now()) do
      # the publishing date is in the past, just leave it
      {:ok, entry}
    else
      args = %{schema: schema, id: id, user_id: user_id(user), status: :published}
      entry_identifier = Identifier.identifier_for(entry)

      Repo.delete_all(
        from j in Oban.Job,
          where: fragment("? @> ?", j.args, ^args)
      )

      args
      |> Worker.EntryPublisher.new(
        replace_args: true,
        scheduled_at: publish_at,
        tags: [:publisher, :status],
        meta: %{identifier: job_identifier(entry_identifier)}
      )
      |> Oban.insert()

      {:ok, entry}
    end
  end

  def schedule_publishing(entry, _, _), do: {:ok, entry}

  @doc "Schedule a historical revision for restoration and publication."
  def schedule_revision(schema, id, revision_number, publish_at, user) do
    with {:ok, id} <- cast_entry_id(id),
         {:ok, revision_number} <- cast_revision_number(revision_number),
         {:ok, publish_at} <- parse_future_datetime(publish_at) do
      schedule_valid_revision(schema_module(schema), id, revision_number, publish_at, user)
    end
  end

  defp schedule_valid_revision(schema, id, revision_number, publish_at, user) do
    Repo.transaction(fn ->
      lock_entry!(schema, id)

      with {:ok, {revision, {_, decoded_entry}}} <-
             Revisions.get_revision(schema, id, revision_number),
           false <- revision.active,
           :ok <- cancel_revision_job(schema, id, revision_number),
           {1, _} <- Revisions.mark_revision_scheduled(schema, id, revision_number, true),
           args = %{
             schema: to_string(schema),
             id: id,
             revision: revision_number,
             user_id: user_id(user)
           },
           revision_identifier =
             decoded_entry
             |> Identifier.identifier_for()
             |> maybe_add_revision_description(revision),
           {:ok, job} <- insert_revision_job(args, publish_at, revision_identifier) do
        job
      else
        true -> Repo.rollback(:revision_already_active)
        {0, _} -> Repo.rollback(:revision_not_found)
        :error -> Repo.rollback(:revision_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_revision_job(args, publish_at, revision_identifier) do
    args
    |> Worker.EntryPublisher.new(
      scheduled_at: publish_at,
      tags: [:publisher, :revision],
      meta: %{identifier: job_identifier(revision_identifier)},
      unique: [
        fields: [:worker, :args],
        keys: [:schema, :id, :revision],
        period: :infinity,
        states: :incomplete
      ]
    )
    |> Oban.insert()
  end

  @doc "Cancel one scheduled revision and make it eligible for retention again."
  def cancel_scheduled_revision(schema, id, revision_number) do
    with {:ok, id} <- cast_entry_id(id),
         {:ok, revision_number} <- cast_revision_number(revision_number) do
      cancel_valid_scheduled_revision(schema_module(schema), id, revision_number)
    end
  end

  defp cancel_valid_scheduled_revision(schema, id, revision_number) do
    case Repo.transaction(fn ->
           lock_entry!(schema, id)
           :ok = cancel_revision_job(schema, id, revision_number)
           Revisions.mark_revision_scheduled(schema, id, revision_number, false)
           :ok
         end) do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Cancel all revision publishing jobs for an entry."
  def cancel_revision_jobs(schema, id) do
    schema = to_string(schema)

    from(j in Oban.Job,
      where:
        j.worker == ^inspect(Worker.EntryPublisher) and
          j.state in ["available", "scheduled", "executing", "retryable"] and
          fragment("? @> ?", j.args, ^%{"schema" => schema, "id" => id})
    )
    |> Oban.cancel_all_jobs()

    :ok
  end

  defp cancel_revision_job(schema, id, revision_number) do
    schema = to_string(schema)

    from(j in Oban.Job,
      where:
        j.worker == ^inspect(Worker.EntryPublisher) and
          j.state in ["available", "scheduled", "executing", "retryable"] and
          fragment(
            "? @> ?",
            j.args,
            ^%{
              "schema" => schema,
              "id" => id,
              "revision" => revision_number
            }
          )
    )
    |> Oban.cancel_all_jobs()

    :ok
  end

  defp lock_entry!(schema, id) do
    query = from(entry in schema, where: entry.id == ^id, select: entry.id, lock: "FOR UPDATE")

    case Repo.one(query) do
      nil -> Repo.rollback(:entry_not_found)
      _entry_id -> :ok
    end
  end

  defp schema_module(schema) when is_atom(schema), do: schema
  defp schema_module(schema) when is_binary(schema), do: Module.concat([schema])

  defp maybe_add_revision_description(nil, _revision), do: nil
  defp maybe_add_revision_description(identifier, %{description: nil}), do: identifier
  defp maybe_add_revision_description(identifier, %{description: ""}), do: identifier

  defp maybe_add_revision_description(identifier, %{description: description}),
    do: Map.update!(identifier, :title, &"#{&1} (#{description})")

  defp job_identifier(nil), do: nil

  defp job_identifier(%_{} = identifier) do
    identifier
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  defp job_identifier(identifier), do: identifier

  # if we have no publish_at but status = pending -- set status published
  def maybe_override_status(%{changes: %{publish_at: nil}} = changeset) do
    status = Changeset.get_field(changeset, :status)

    if status == :pending do
      Changeset.put_change(changeset, :status, :published)
    else
      changeset
    end
  end

  def maybe_override_status(%{changes: %{publish_at: publish_at}} = changeset) when not is_nil(publish_at) do
    status = Changeset.get_field(changeset, :status)

    if DateTime.after?(publish_at, DateTime.utc_now()) do
      if status in [:pending, :published] do
        Changeset.put_change(changeset, :status, :pending)
      else
        changeset
      end
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

    {:ok, Repo.all(query)}
  end

  def delete_job(id) do
    with {:ok, id} <- cast_entry_id(id),
         %Oban.Job{} = job <- Repo.get(Oban.Job, id),
         :ok <- Oban.cancel_job(job) do
      clear_revision_schedule(job)
      Repo.delete_all(from j in Oban.Job, where: j.id == ^id)
    else
      nil -> {0, nil}
      {:error, _reason} = error -> error
    end
  end

  defp clear_revision_schedule(%Oban.Job{
         args: %{"schema" => schema, "id" => id, "revision" => revision_number}
       }) do
    Revisions.mark_revision_scheduled(schema_module(schema), id, revision_number, false)
  end

  defp clear_revision_schedule(_job), do: :ok

  defp parse_future_datetime(%DateTime{} = datetime) do
    if DateTime.after?(datetime, DateTime.utc_now()) do
      {:ok, datetime}
    else
      {:error, :publish_at_must_be_in_the_future}
    end
  end

  defp parse_future_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, parsed, _offset} -> parse_future_datetime(parsed)
      {:error, _reason} -> {:error, :invalid_publish_at}
    end
  end

  defp parse_future_datetime(_datetime), do: {:error, :invalid_publish_at}

  defp cast_revision_number(revision) when is_integer(revision), do: {:ok, revision}

  defp cast_revision_number(revision) when is_binary(revision) do
    case Integer.parse(revision) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_revision}
    end
  end

  defp cast_revision_number(_revision), do: {:error, :invalid_revision}

  defp cast_entry_id(id) when is_integer(id), do: {:ok, id}

  defp cast_entry_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_entry_id}
    end
  end

  defp cast_entry_id(_id), do: {:error, :invalid_entry_id}

  defp user_id(:system), do: nil
  defp user_id(%{id: id}), do: id
end
