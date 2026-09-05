defmodule Brando.Worker.DraftPurger do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(_job) do
    Brando.Drafts.purge()
    :ok
  end
end
