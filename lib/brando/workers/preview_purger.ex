defmodule Brando.Worker.PreviewPurger do
  @moduledoc """
  A Worker for purging previews
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Brando.Sites

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}) do
    case Sites.delete_preview(id) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(5)
end
