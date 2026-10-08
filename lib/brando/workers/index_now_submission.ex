defmodule Brando.Worker.IndexNowSubmission do
  @moduledoc """
  Sends one batch of URLs to IndexNow (`Brando.IndexNow`), in the site
  environment that gathered it. Scheduled `batch_seconds` after the first URL;
  URLs from saves in between are added to it while it waits.

  No answer, `429` and server errors are tried again with Oban's backoff; any
  other answer is recorded and the batch is done.
  """
  use Oban.Worker, queue: :webhooks, max_attempts: 5

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"urls" => urls}} = job) when is_list(urls) do
    TenantJob.run(job, fn -> Brando.IndexNow.submit(urls) end)
  end

  def perform(_job), do: {:cancel, :invalid_args}

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)
end
