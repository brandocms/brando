defmodule Brando.Repo.Migrations.Brando225RenameHtmlVarsToRichText do
  use Ecto.Migration

  @moduledoc """
  In every site environment, the `html` var type is called `rich_text`: the
  editor has always shown it as rich text, and its value is now sanitized
  as rich text is, on save and when it renders. Renames the type of module,
  block, page, global set and table vars (`content_vars.type`).

  Values are left as they are: a value saved before with markup that is not
  safe renders as its text alone, and saving it again asks for safe markup.

  Down names the type `html` again.
  """

  def up do
    for prefix <- prefixes() do
      execute(~s(UPDATE "#{prefix}".content_vars SET type = 'rich_text' WHERE type = 'html'))
    end
  end

  def down do
    for prefix <- prefixes() do
      execute(~s(UPDATE "#{prefix}".content_vars SET type = 'html' WHERE type = 'rich_text'))
    end
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end
