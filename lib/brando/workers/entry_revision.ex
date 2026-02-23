defmodule Brando.Worker.EntryRevision do
  @moduledoc """
  Background worker for creating entry revisions.

  Moves the expensive revision creation (full preload + binary serialization)
  out of the synchronous save path.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"schema" => schema, "entry_id" => entry_id, "user_id" => user_id}}) do
    schema = Module.concat([schema])
    Logger.info("==> [OBAN] Creating revision for #{inspect(schema)} ##{entry_id}")
    entry = Brando.Repo.get!(schema, entry_id)
    user = if user_id, do: Brando.Users.get_user!(user_id), else: :system
    Brando.Revisions.create_revision(entry, user)
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)
end
