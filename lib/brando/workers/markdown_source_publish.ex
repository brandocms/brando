defmodule Brando.Worker.MarkdownSourcePublish do
  @moduledoc false
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:args], states: [:available, :scheduled, :executing, :retryable, :completed]]

  def perform(job), do: Brando.Tenant.Job.run(job, fn -> Brando.MarkdownSources.Publication.publish(job.args) end)
end
