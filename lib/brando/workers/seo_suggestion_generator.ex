defmodule Brando.Worker.SEOSuggestionGenerator do
  @moduledoc """
  Writes one queued `Brando.SEO.Suggestion`. The entry itself is not touched:
  the text waits for an editor in the Content SEO tab.

  Provider hiccups are retried; a reason no retry can fix (no AI configured,
  nothing on the entry to describe, the entry gone) fails the suggestion at
  once, and so does the last attempt, so the tab never waits on a job that
  has stopped.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:tenant_prefix, :suggestion_id], states: :incomplete]

  alias Brando.SEO.Generate
  alias Brando.SEO.Suggestion
  alias Brando.SEO.Suggestions
  alias Brando.Tenant.Job, as: TenantJob

  @permanent [
    :disabled,
    :missing_model,
    :missing_api_key,
    :invalid_model,
    :no_context,
    :unsupported_field,
    :unknown_schema,
    :unsupported_format,
    :image_file_missing,
    :no_image_input
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(90)

  defp perform_tenant(%Oban.Job{args: %{"suggestion_id" => id}} = job) do
    case Brando.Repo.get(Suggestion, id) do
      %Suggestion{status: :queued} = suggestion -> generate(suggestion, job)
      # Reviewed, replaced or deleted since it was queued.
      _ -> :ok
    end
  end

  defp generate(suggestion, job) do
    result =
      case Suggestion.schema_module(suggestion) do
        nil ->
          {:error, :unknown_schema}

        _schema when suggestion.field == :alt ->
          Brando.Images.AltText.describe(suggestion.entry_id)

        schema ->
          # Written as :system — and not persisted, so no edit is attributed.
          Generate.generate(schema, suggestion.entry_id, suggestion.field, :system, persist: false)
      end

    case result do
      {:ok, %{text: text, model: model}} ->
        {:ok, _} = Suggestions.fill(suggestion, text, model)
        Suggestions.broadcast(suggestion.language)
        :ok

      {:error, reason} ->
        if permanent?(reason) or job.attempt >= job.max_attempts do
          {:ok, _} = Suggestions.fail(suggestion, Brando.AI.error_message(reason))
          Suggestions.broadcast(suggestion.language)
          {:cancel, reason}
        else
          {:error, reason}
        end
    end
  end

  defp permanent?(reason) when reason in @permanent, do: true
  defp permanent?({_schema, :not_found}), do: true
  defp permanent?(_), do: false
end
