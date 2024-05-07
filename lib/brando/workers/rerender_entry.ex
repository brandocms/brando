defmodule Brando.Worker.ReRenderEntry do
  use Oban.Worker, queue: :default, max_attempts: 5
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id, "schema" => schema}}) do
    schema = Module.concat([schema])
    Brando.Villain.rerender_html_from_id(id, schema)
    Logger.info("==> [CRON] Re-rendering entry #{id} for schema #{schema}")
    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(30)
end
