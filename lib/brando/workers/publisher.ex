defmodule Brando.Worker.Publisher do
  @moduledoc """
  A Worker for publishing and unpublishing entries
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 10,
    unique: [keys: [:schema, :id, :status], period: :infinity]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"schema" => schema, "id" => id, "status" => status, "user_id" => user_id}
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
