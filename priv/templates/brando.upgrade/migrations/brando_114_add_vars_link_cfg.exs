defmodule Brando.Repo.Migrations.AddVarsLinkCfg do
  use Ecto.Migration

  def up do
    alter table(:content_vars) do
      add :link_text, :string
      add :link_identifier_schemas, {:array, :string}, default: []
      add :link_allow_custom_text, :boolean, default: true
      add :link_target_blank, :boolean, default: false
      add :link_type, :string, default: "url"
    end
  end

  def down do
    alter table(:content_vars) do
      remove :link_text
      remove :link_identifier_schemas
      remove :link_allow_custom_text
      remove :link_target_blank
      remove :link_type
    end
  end
end
