defmodule Brando.Repo.Migrations.ContentSectionsToPalettes do
  use Ecto.Migration
  import Ecto.Query

  def change do
    create table(:content_palettes) do
      add :name, :text
      add :key, :text
      add :namespace, :text
      add :sequence, :integer
      add :global, :boolean, default: false
      add :instructions, :text
      add :colors, :jsonb

      timestamps()
    end

    flush()

    query =
      from m in "content_sections",
        select: %{
          id: m.id,
          name: m.name,
          namespace: m.namespace,
          instructions: m.instructions,
          color_bg: m.color_bg,
          color_fg: m.color_fg,
          color_accent: m.color_accent,
          creator_id: m.creator_id
        }

    sections = Brando.repo().all(query)

    for section <- sections do
      new_palette = %Brando.Content.Palette{
        name: section.name,
        key: Recase.to_camel(section.name),
        namespace: section.namespace,
        instructions: section.instructions,
        global: false,
        creator_id: section.creator_id,
        colors: [
          %Brando.Content.Palette.Color{name: "Background Color", key: "backgroundColor", hex_value: section.color_bg},
          %Brando.Content.Palette.Color{name: "Foreground Color", key: "foregroundColor", hex_value: section.color_fg},
          %Brando.Content.Palette.Color{name: "Accent Color", key: "accentColor", hex_value: section.color_accent},
        ]
      }

      Brando.repo().insert!(new_palette)
    end

    drop table(:content_sections)
  end
end
