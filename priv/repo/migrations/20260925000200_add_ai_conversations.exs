defmodule Brando.Repo.Migrations.Brando185AddAiConversations do
  use Ecto.Migration

  @moduledoc """
  Conversations, messages and runs of the admin content agent
  (`Brando.AI.Agent`). Like content proposals they live in `public`, scoped
  by site and environment, and belong to one user.
  """

  def change do
    create table(:ai_conversations, primary_key: false, prefix: "public") do
      add :id, :uuid, primary_key: true
      add :scope, :text, null: false
      add :actor_id, references(:users, prefix: "public", on_delete: :delete_all), null: false
      add :title, :text
      add :language, :text
      add :proposal_id, :uuid
      add :attachments, {:array, :map}, null: false, default: []
      add :archived_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:ai_conversations, [:scope, :actor_id, :updated_at], prefix: "public")

    create table(:ai_messages, primary_key: false, prefix: "public") do
      add :id, :uuid, primary_key: true

      add :conversation_id, references(:ai_conversations, type: :uuid, prefix: "public", on_delete: :delete_all),
        null: false

      add :run_id, :uuid
      add :role, :text, null: false
      add :content, :text
      add :tool_calls, {:array, :map}, null: false, default: []
      add :tool_call_id, :text
      add :tool_name, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ai_messages, [:conversation_id, :inserted_at], prefix: "public")

    create table(:ai_runs, primary_key: false, prefix: "public") do
      add :id, :uuid, primary_key: true

      add :conversation_id, references(:ai_conversations, type: :uuid, prefix: "public", on_delete: :delete_all),
        null: false

      add :scope, :text, null: false
      add :status, :text, null: false, default: "running"
      add :model, :text
      add :steps, :integer, null: false, default: 0
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cached_tokens, :integer, null: false, default: 0
      add :reasoning_tokens, :integer, null: false, default: 0
      add :reserved_tokens, :integer, null: false, default: 0
      add :cost, :float, null: false, default: 0.0
      add :error, :text
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:ai_runs, [:scope, :inserted_at], prefix: "public")
    create index(:ai_runs, [:conversation_id], prefix: "public")
  end
end
