defmodule BrandoIntegration.Repo.Migrations.AddContentDefinitionApplies do
  use Ecto.Migration

  # Mirrors the brando_231 upgrade migration for the test schema.
  @moduledoc """
  `content_definition_applies`: each database's own baseline of module
  definitions applied from files (`Brando.Content.DefinitionApply`).
  """

  def change do
    create table(:content_definition_applies) do
      add :kind, :text, null: false
      add :uid, :text, null: false
      add :digest, :text, null: false
      add :previous_digest, :text
      add :previous, :map
      add :action, :text, null: false
      add :source, :text, null: false
      add :release, :text
      add :references, :map, null: false, default: %{}
      add :batch_id, :uuid, null: false
      add :applied_by_id, references(:users, on_delete: :nilify_all)
      add :applied_at, :utc_datetime_usec, null: false
    end

    create index(:content_definition_applies, [:kind, :uid, :id])
    create index(:content_definition_applies, [:batch_id])
  end
end
