defmodule Brando.Worker.EntryRenderer do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 5

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entry_id" => entry_id, "schema" => schema}}) do
    schema = Module.concat([schema])
    Logger.info("==> [CRON] Rendering entry #{entry_id} for schema #{schema}")
    Brando.Villain.render_entry(schema, entry_id)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
