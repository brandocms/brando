defmodule Brando.Repo.Migrations.AddVarLayout do
  use Ecto.Migration

  @moduledoc """
  Mirrors `brando_156_add_var_layout` for the test and e2e databases.

  `new_row` marks a row break so the block editor can derive rows by packing
  `width` into 12 units, and `placement` replaces the `important` boolean with
  a three-way choice — the third value, `hidden`, is new: a template-only
  constant editors never see.
  """

  def up do
    alter table(:content_vars) do
      add :new_row, :boolean, default: false
      add :placement, :string, default: "content"
    end

    # important? -> shown inline in the block. Otherwise it lived behind the
    # block's Configure modal, which is exactly what :config means.
    execute """
    UPDATE content_vars
       SET placement = CASE WHEN important IS TRUE THEN 'content' ELSE 'config' END
    """

    # Every var used to start its own row in practice, since the old 12-column
    # grid packed them densely and authors had no way to group them.
    execute """
    UPDATE content_vars SET new_row = TRUE
    """

    alter table(:content_vars) do
      remove :important
    end
  end

  def down do
    alter table(:content_vars) do
      add :important, :boolean, default: false
    end

    execute """
    UPDATE content_vars SET important = (placement = 'content')
    """

    execute """
    UPDATE content_vars SET width = 'full' WHERE width IN ('fourth', 'auto', 'fill')
    """

    alter table(:content_vars) do
      remove :new_row
      remove :placement
    end
  end
end
