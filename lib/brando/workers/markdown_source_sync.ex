defmodule Brando.Worker.MarkdownSourceSync do
  @moduledoc "Reconciles the current configured ref; webhook commit order is never publication order."
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: 60, fields: [:args], states: [:available, :scheduled, :retryable]]

  import Ecto.Query, only: [from: 2]
  alias Brando.MarkdownSources
  alias Brando.MarkdownSources.{Connection, Renderer, Source, Version}
  alias Brando.Repo

  def perform(%Oban.Job{args: args} = job) do
    Brando.Tenant.Job.run(job, fn ->
      with {:ok, connection} <- Connection.current(args["connection"]),
           true <- args["generation"] == Connection.generation(connection) do
        sources =
          if args["source_id"],
            do: List.wrap(MarkdownSources.get_source(args["source_id"])),
            else:
              Repo.all(
                from(s in Source,
                  where: s.connection == ^args["connection"] and s.ref == ^args["ref"] and s.enabled,
                  order_by: s.id
                )
              )

        Enum.reduce(sources, :ok, fn source, result ->
          case sync(source.id, connection) do
            :ok -> result
            {:cancel, _} -> result
            error -> error
          end
        end)
      else
        _ -> {:cancel, :connection_changed}
      end
    end)
  end

  def timeout(_), do: :timer.minutes(10)

  def sync(id, connection) do
    key = "markdown-source:#{Brando.Tenant.current_prefix()}:#{id}"

    Brando.Tenant.Lock.with(key, fn ->
      with %Source{enabled: true} = source <- MarkdownSources.get_source(id),
           true <- source.connection == connection.key,
           {:ok, current} <- Connection.current(source.connection),
           true <- Connection.generation(current) == Connection.generation(connection) do
        fetch_and_import(source, current)
      else
        _ -> {:cancel, :source_changed}
      end
    end)
  end

  defp fetch_and_import(source, connection) do
    provider = Application.get_env(:brando, :markdown_sources_provider, Brando.MarkdownSources.GitHub)

    with {:ok, document} <- provider.fetch(connection, source),
         {:ok, html} <- Renderer.render(document),
         {:ok, updated} <- import_document(source, connection, document, html) do
      MarkdownSources.broadcast(updated)
    else
      {:error, reason} -> fail(source, reason)
    end
  rescue
    _ -> fail(source, :synchronization_failed)
  end

  defp import_document(source, connection, document, html) do
    Repo.transaction(fn ->
      current = Repo.one!(from(s in Source, where: s.id == ^source.id, lock: "FOR UPDATE"))

      unless current.lock_version == source.lock_version and current.enabled and
               Connection.same_generation?(current.connection, Connection.generation(connection)),
             do: Repo.rollback(:source_changed)

      version =
        Repo.get_by(Version, source_id: source.id, commit: document.commit) ||
          Repo.insert!(
            struct(
              Version,
              Map.merge(document, %{
                source_id: source.id,
                html: html,
                content_hash: :crypto.hash(:sha256, html) |> Base.encode16(case: :lower)
              })
            )
          )

      previous = MarkdownSources.get_version(source.id, current.latest_version_id)
      changed? = is_nil(previous) or previous.content_hash != version.content_hash

      updated =
        current
        |> Ecto.Changeset.change(%{
          latest_version_id: version.id,
          last_checked_at: DateTime.utc_now(),
          last_error: nil,
          publication_sequence: current.publication_sequence + if(changed?, do: 1, else: 0),
          publication_status: if(changed?, do: "Rendered", else: current.publication_status)
        })
        |> Repo.update!()

      if changed? do
        source.id |> MarkdownSources.consumer_entries() |> Brando.MarkdownSources.Publication.render_consumers!()
        MarkdownSources.audit(source, "source.imported", :system, %{version_id: version.id})

        case Brando.MarkdownSources.Publication.enqueue(updated, connection) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
      end

      updated
    end)
  end

  defp fail(source, reason) do
    reason = if is_atom(reason), do: reason, else: :synchronization_failed
    current = MarkdownSources.get_source(source.id)

    if current && current.lock_version == source.lock_version do
      current
      |> Ecto.Changeset.change(last_error: Atom.to_string(reason), last_checked_at: DateTime.utc_now())
      |> Repo.update!()

      MarkdownSources.audit(source, "source.failed", :system, %{message: Atom.to_string(reason)})
      MarkdownSources.broadcast(source)
    end

    {:error, reason}
  end
end
