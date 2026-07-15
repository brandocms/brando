defmodule Brando.Worker.EntryPublisher do
  @moduledoc """
  A Worker for publishing and unpublishing entries
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 10

  require Logger
  alias Brando.Revisions

  # schedule publishing/depublishing an entry
  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{
            "schema" => schema,
            "id" => id,
            "revision" => revision,
            "user_id" => user_id
          }
        } = job
      ) do
    user = publisher_user(user_id)
    now = DateTime.utc_now()

    single =
      schema
      |> String.split(".")
      |> List.last()
      |> String.downcase()

    schema = Module.concat(List.wrap(schema))

    case Revisions.set_entry_to_revision(schema, id, revision, user, publish?: true) do
      {:ok, new_entry} ->
        Logger.info("""

        ==> [B/Pub] Published revision ##{revision} of #{single} ##{id}
        ==> [B/Pub] @ #{now.day}/#{now.month}/#{now.year} #{now.hour}:#{now.minute}:#{now.second} UTC
        """)

        BrandoAdmin.LiveView.Listing.update_list_entries(schema)
        {:ok, new_entry}

      {:error, reason} ->
        release_failed_revision_schedule(job, schema, id, revision)
        {:error, reason}
    end
  end

  # schedule publishing/depublishing an entry
  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "schema" => schema,
          "id" => id,
          "status" => status,
          "user_id" => user_id
        }
      }) do
    user = publisher_user(user_id)
    now = DateTime.utc_now()

    params = %{
      creator_id: user_id,
      status: status
    }

    params =
      if status == "published" do
        Map.put(params, :publish_at, DateTime.utc_now())
      end

    schema_module = Module.concat(List.wrap(schema))
    context = schema_module.__modules__().context
    singular = schema_module.__naming__().singular

    case apply(context, :"update_#{singular}", [id, params, user]) do
      {:ok, _} ->
        Logger.info("""

        ==> [B/Pub] #{(status == "published" && "Published") || "Depublished"} #{singular} ##{id}
        ==> [B/Pub] @ #{now.day}/#{now.month}/#{now.year} #{now.hour}:#{now.minute}:#{now.second} UTC
        """)

        BrandoAdmin.LiveView.Listing.update_list_entries(schema_module)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  defp publisher_user(nil), do: :system

  defp publisher_user(user_id) do
    case Brando.Users.get_user(user_id) do
      {:ok, user} -> user
      _ -> :system
    end
  end

  defp release_failed_revision_schedule(
         %Oban.Job{attempt: attempt, max_attempts: max_attempts},
         schema,
         id,
         revision
       )
       when is_integer(attempt) and is_integer(max_attempts) and attempt >= max_attempts do
    Revisions.mark_revision_scheduled(schema, id, revision, false)
  end

  defp release_failed_revision_schedule(_job, _schema, _id, _revision), do: :ok
end
