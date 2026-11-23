defmodule Brando.Migrations.Brando245AddUidsToPalettesAndContainersTest do
  # Runs the upgrade template inside the sandbox transaction, with the
  # columns dropped first; Postgres DDL is transactional, so everything is
  # undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_245_add_uids_to_palettes_and_containers.exs"
  @tenant "tenant_acme_staging"

  defp palette!(schema, namespace, key, deleted? \\ false) do
    [[id]] =
      rows(
        ~s|INSERT INTO "#{schema}".content_palettes (name, namespace, key, colors, deleted_at, inserted_at, updated_at) | <>
          ~s|VALUES ('Palette', $1, $2, '[]', $3, now(), now()) RETURNING id|,
        [namespace, key, if(deleted?, do: ~N[2026-01-01 00:00:00])]
      )

    id
  end

  defp container!(schema, namespace, name) do
    [[id]] =
      rows(
        ~s|INSERT INTO "#{schema}".content_containers (name, namespace, code, type, inserted_at, updated_at) | <>
          ~s|VALUES ($1, $2, '{{ content }}', 'liquid', now(), now()) RETURNING id|,
        [name, namespace]
      )

    id
  end

  defp uid(schema, table, id), do: rows(~s|SELECT uid FROM "#{schema}".#{table} WHERE id = $1|, [id]) |> hd() |> hd()

  test "derives each palette's and container's uid from what two environments seeded alike share" do
    for table <- ~w(content_palettes content_containers), do: query!("ALTER TABLE public.#{table} DROP COLUMN uid")
    create_environment(@tenant, ~w(content_modules content_table_templates content_palettes content_containers))

    for schema <- ["public", @tenant] do
      paper = palette!(schema, "site", "paper")
      # Derives the same uid as the one before it, and comes second
      clash = palette!(schema, "site-paper", "")
      # In the trash: the active row keeps the plain uid
      trashed = palette!(schema, "site", "darkMode", true)
      dark = palette!(schema, "site", "darkMode")
      tinted = container!(schema, "Sections", "Tinted section")
      empty = container!(schema, "", "")

      version = up(@template)

      assert uid(schema, "content_palettes", paper) == "palette-site-paper"
      assert uid(schema, "content_palettes", clash) == "palette-site-paper-2"
      assert uid(schema, "content_palettes", dark) == "palette-site-darkmode"
      assert uid(schema, "content_palettes", trashed) == "palette-site-darkmode-2"
      assert uid(schema, "content_containers", tinted) == "container-sections-tinted-section"
      assert uid(schema, "content_containers", empty) == "container-#{empty}"

      # A row added later gets its own; one with a uid keeps it
      query!(~s|UPDATE "#{schema}".content_palettes SET uid = 'kept' WHERE id = $1|, [paper])
      later = palette!(schema, "site", "paper")
      up(@template)
      assert uid(schema, "content_palettes", paper) == "kept"
      assert uid(schema, "content_palettes", later) == "palette-site-paper"

      for table <- ~w(content_palettes content_containers) do
        assert Enum.any?(indexes(schema, table), &(&1 =~ "UNIQUE INDEX" and &1 =~ "(uid)"))
      end

      if schema == @tenant do
        down(@template, version)
        for prefix <- ["public", @tenant], do: refute("uid" in columns(prefix, "content_palettes"))
      end
    end
  end

  # A full snapshot refuses two definitions with one uid, whatever their kinds
  test "passes over a uid a module or a table template already has" do
    for table <- ~w(content_palettes content_containers), do: query!("ALTER TABLE public.#{table} DROP COLUMN uid")

    query!(
      "INSERT INTO public.content_modules (name, namespace, help_text, code, uid, inserted_at, updated_at) " <>
        ~s|VALUES ('{"en": "M"}', '{"en": "site"}', '{}', '', 'palette-site-paper', now(), now())|
    )

    query!(
      "INSERT INTO public.content_table_templates (name, uid, inserted_at, updated_at) " <>
        "VALUES ('T', 'container-sections-tinted', now(), now())"
    )

    paper = palette!("public", "site", "paper")
    # Derives the uid the container below derives
    tinted_palette = palette!("public", "container-sections", "tinted")
    tinted = container!("public", "Sections", "Tinted")

    up(@template)

    assert uid("public", "content_palettes", paper) == "palette-site-paper-2"
    assert uid("public", "content_palettes", tinted_palette) == "palette-container-sections-tinted"
    assert uid("public", "content_containers", tinted) == "container-sections-tinted-2"
  end
end
