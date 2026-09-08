defmodule Brando.MarkdownSources.Migration do
  @moduledoc false
  use Ecto.Migration

  def content_up(prefix \\ nil) do
    create table(:content_markdown_sources, prefix: prefix) do
      add :name, :text, null: false
      add :connection, :text, null: false
      add :ref, :text, null: false
      add :path, :text, null: false
      add :enabled, :boolean, null: false, default: true
      add :latest_version_id, :bigint
      add :last_checked_at, :utc_datetime_usec
      add :last_error, :text
      add :publication_sequence, :bigint, null: false, default: 0
      add :publication_status, :text, null: false, default: "Not imported"
      add :build_id, :bigint
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:content_markdown_sources, [:connection, :ref, :path], prefix: prefix)

    create table(:content_markdown_versions, prefix: prefix) do
      add :source_id, references(:content_markdown_sources, prefix: prefix, on_delete: :restrict), null: false
      add :commit, :text, null: false
      add :content_hash, :text, null: false
      add :markdown, :text, null: false
      add :html, :text, null: false
      add :repository, :text, null: false
      add :path, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:content_markdown_versions, [:source_id, :commit], prefix: prefix)

    create table(:content_markdown_events, prefix: prefix) do
      add :source_id, :bigint
      add :version_id, :bigint
      add :actor_id, :bigint
      add :action, :text, null: false
      add :message, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:content_markdown_events, [:source_id, :id], prefix: prefix)

    create index(:content_refs, ["(data->'data'->>'source_id')", "(data->'data'->>'policy')"],
             name: :content_refs_markdown_source_index,
             prefix: prefix,
             where: "data->>'type' = 'markdown_source' AND block_id IS NOT NULL"
           )
  end

  def content_down(prefix \\ nil) do
    drop_if_exists index(:content_refs, [], name: :content_refs_markdown_source_index, prefix: prefix)
    drop table(:content_markdown_events, prefix: prefix)
    drop table(:content_markdown_versions, prefix: prefix)
    drop table(:content_markdown_sources, prefix: prefix)
  end

  def shared_up do
    create table(:markdown_webhook_deliveries, prefix: "public") do
      add :connection, :text, null: false
      add :delivery_id, :text, null: false
      add :fingerprint, :text, null: false
      add :job_ids, {:array, :bigint}, null: false, default: []
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:markdown_webhook_deliveries, [:connection, :delivery_id], prefix: "public")
    create unique_index(:markdown_webhook_deliveries, [:connection, :fingerprint], prefix: "public")
  end

  def shared_down, do: drop(table(:markdown_webhook_deliveries, prefix: "public"))
end
