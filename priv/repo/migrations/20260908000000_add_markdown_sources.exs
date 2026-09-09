defmodule Brando.Repo.Migrations.Brando171AddMarkdownSources do
  use Ecto.Migration

  def up do
    Brando.MarkdownSources.Migration.shared_up()
    Enum.each(prefixes(), &Brando.MarkdownSources.Migration.content_up/1)

    alter table(:ssg_builds, prefix: "public") do
      add :markdown_context, :map, null: false, default: %{}
    end
  end

  def down do
    alter table(:ssg_builds, prefix: "public") do
      remove :markdown_context
    end

    Enum.each(prefixes(), &Brando.MarkdownSources.Migration.content_down/1)
    Brando.MarkdownSources.Migration.shared_down()
  end

  defp prefixes do
    %{rows: rows} =
      repo().query!(
        "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
      )

    Enum.map(rows, &hd/1)
  end
end
