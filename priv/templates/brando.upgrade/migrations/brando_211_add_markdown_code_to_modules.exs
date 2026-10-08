defmodule Brando.Repo.Migrations.Brando211AddMarkdownCodeToModules do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `content_modules.markdown_code` holds a module's
  optional Markdown template, used for entries' Markdown alternates
  (`Brando.Villain.Markdown`). Empty turns the module's HTML into Markdown.
  """

  def up do
    for prefix <- prefixes() do
      alter table(:content_modules, prefix: prefix) do
        add :markdown_code, :text
      end
    end
  end

  def down do
    for prefix <- prefixes() do
      alter table(:content_modules, prefix: prefix) do
        remove :markdown_code
      end
    end
  end

  defp prefixes do
    %{rows: rows} =
      repo().query!(
        "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
      )

    Enum.map(rows, &hd/1)
  end
end
