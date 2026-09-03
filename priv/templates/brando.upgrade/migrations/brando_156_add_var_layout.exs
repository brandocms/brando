defmodule Brando.Repo.Migrations.AddVarLayout do
  use Ecto.Migration

  @moduledoc """
  Gives vars an authored editor layout.

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

    # No var carried an authored row break before this migration: the old
    # 12-column grid packed them densely and authors had no way to group them.
    # `Brando.Content.Var.Layout.pack/1` breaks a row on its own whenever the
    # next var would overflow the 12 units or the 4 slots, so leaving every
    # `new_row` false reproduces that packing exactly. Setting them true instead
    # pushes every var onto a line of its own.
    execute """
    UPDATE content_vars SET new_row = FALSE
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
