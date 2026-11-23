defmodule Brando.Migrations.Brando248AddImagesSourcesTest do
  # Runs the upgrade template inside the sandbox transaction; Postgres DDL is
  # transactional, so everything is undone afterwards.
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_248_add_images_sources.exs"
  @table "images_sources"
  @acme "tenant_acme_production"
  @other "tenant_other_production"

  # The test schema's table, its foreign key pointing into `prefix`
  defp expected(prefix) do
    {columns, indexes, references} = table_set("public", [@table])[@table]
    {columns, indexes, Enum.map(references, fn {column, "public", target} -> {column, prefix, target} end)}
  end

  defp image!(prefix) do
    [[id]] =
      rows(~s{INSERT INTO "#{prefix}".images (path, inserted_at, updated_at) VALUES ('a.jpg', now(), now()) RETURNING id})

    id
  end

  # As `Brando.Images.Source.record/5` writes it: once per image, source, ref and variant
  defp source!(prefix, image, variant \\ nil) do
    query!(
      ~s{INSERT INTO "#{prefix}".#{@table} (image_id, source, ref, variant, config_target, inserted_at)
         VALUES ($1, 'figma', 'ref-a', $2, 'default', now()) ON CONFLICT DO NOTHING},
      [image, variant]
    )
  end

  defp count(prefix), do: rows(~s{SELECT count(*) FROM "#{prefix}".#{@table}}) |> hd() |> hd()

  test "creates the table in public and every environment with images, as the test schema has it, and drops it" do
    expected = Map.new(["public", @acme, @other], &{&1, expected(&1)})
    query!("DROP TABLE #{@table}")
    create_environment(@acme, ["images"])
    create_environment(@other, ["images"])
    create_environment("tenant_bare_production")

    version = up(@template)

    for prefix <- ["public", @acme, @other] do
      assert table_set(prefix, [@table])[@table] == expected[prefix]
    end

    refute table?("tenant_bare_production", @table)

    # One row per image, source, ref and variant, an upright one included
    acme = image!(@acme)
    other = image!(@other)

    for _twice <- 1..2, do: source!(@acme, acme)
    source!(@acme, acme, "90")
    source!(@other, other)
    assert count(@acme) == 2

    # The rows go with their image, in its own environment only
    query!(~s{DELETE FROM "#{@acme}".images WHERE id = $1}, [acme])
    assert count(@acme) == 0
    assert count(@other) == 1

    down(@template, version)

    for prefix <- ["public", @acme, @other], do: refute(table?(prefix, @table))
  end

  test "an environment provisioned from the upgraded public has the table, and running it there changes nothing" do
    provision(@acme)
    assert table_set(@acme, [@table])[@table] == expected(@acme)
    source!(@acme, image!(@acme))

    up(@template)

    assert table_set(@acme, [@table])[@table] == expected(@acme)
    assert count(@acme) == 1
  end
end
