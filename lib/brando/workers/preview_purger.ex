defmodule Brando.Worker.PreviewPurger do
  @moduledoc """
  A Worker for purging previews
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 10

  alias Brando.Sites

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}) do
    Sites.delete_preview(id)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(5)
end
