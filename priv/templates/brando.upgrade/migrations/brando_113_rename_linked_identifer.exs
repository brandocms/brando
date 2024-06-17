defmodule Brando.Repo.Migrations.RenameLinkedIdentifier do
  use Ecto.Migration

  def up do
    rename table(:content_vars), :linked_identifier_id, to: :identifier_id
  end

  def down do
    rename table(:content_vars), :identifier_id, to: :linked_identifier_id
  end
end
