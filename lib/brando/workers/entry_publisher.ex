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
  def perform(%Oban.Job{
        args: %{
          "schema" => schema,
          "id" => id,
          "revision" => revision,
          "user_id" => user_id
        }
      }) do
    {:ok, user} = Brando.Users.get_user(user_id)
    now = DateTime.utc_now()

    single =
      schema
      |> String.split(".")
      |> List.last()
      |> String.downcase()

    case Revisions.set_entry_to_revision(schema, id, revision, user) do
      {:ok, new_entry} ->
        Logger.info("""

        ==> [B/Pub] Published revision ##{revision} of #{single} ##{id}
        ==> [B/Pub] @ #{now.day}/#{now.month}/#{now.year} #{now.hour}:#{now.minute}:#{now.second} UTC
        """)

        {:ok, new_entry}

      err ->
        {:error, err}
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
    {:ok, user} = Brando.Users.get_user(user_id)
    now = DateTime.utc_now()

    params = %{
      creator_id: user_id,
      status: status
    }

    params =
      if status == "published" do
        Map.put(params, :publish_at, DateTime.utc_now())
      end

    require Logger
    Logger.error("-- pub")
    Logger.error(inspect(schema, pretty: true))

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

      err ->
        {:error, err}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(5)
end
