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
          "user_id" => _user_id
        }
      }) do
    now = DateTime.utc_now()

    single =
      schema
      |> String.split(".")
      |> List.last()
      |> String.downcase()

    case Revisions.set_entry_to_revision(schema, id, revision) do
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
    now = DateTime.utc_now()

    params = %{
      creator_id: user_id,
      status: status
    }

    params =
      if status == "published" do
        Map.put(params, :publish_at, DateTime.utc_now())
      end

    context =
      schema
      |> String.split(".")
      |> Enum.drop(-1)
      |> Module.concat()

    single =
      schema
      |> String.split(".")
      |> List.last()
      |> String.downcase()

    case apply(context, :"update_#{single}", [id, params, %{id: user_id}]) do
      {:ok, _} ->
        Logger.info("""

        ==> [B/Pub] #{(status == "published" && "Published") || "Depublished"} #{single} ##{id}
        ==> [B/Pub] @ #{now.day}/#{now.month}/#{now.year} #{now.hour}:#{now.minute}:#{now.second} UTC
        """)

        :ok

      err ->
        {:error, err}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(5)
end
