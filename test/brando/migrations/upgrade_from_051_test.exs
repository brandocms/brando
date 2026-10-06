defmodule Brando.Migrations.UpgradeFrom051Test do
  # Each test rebuilds the 0.51 tables a template expects inside the sandbox
  # transaction and runs the template. Postgres DDL is transactional, so
  # everything is rolled back afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @templates Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations")

  defp run_template(name) do
    [{module, _bytecode}] = Code.compile_file(Path.join(@templates, name))

    try do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false, migration_lock: false)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  defp query!(sql, params \\ []), do: Repo.query!(sql, params)

  defp rows(sql, params \\ []), do: query!(sql, params).rows

  defp table_exists?(table) do
    rows("SELECT to_regclass($1)::text", [table]) != [[nil]]
  end

  describe "brando_80" do
    test "drops app foreign keys to images_series and keeps their ids" do
      query!("ALTER TABLE images DROP COLUMN config_target")
      query!("CREATE TABLE images_categories (id bigserial PRIMARY KEY, name text)")

      query!("""
      CREATE TABLE images_series (
        id bigserial PRIMARY KEY, name text, slug text, cfg jsonb,
        image_category_id bigint CONSTRAINT imageseries_image_category_id_fkey REFERENCES images_categories
      )
      """)

      query!("ALTER TABLE images ADD COLUMN image_series_id bigint REFERENCES images_series")
      query!("CREATE TABLE legacy_posts (id bigserial PRIMARY KEY, image_series_id bigint REFERENCES images_series)")
      # An app table pointing at the categories as well
      query!(
        "CREATE TABLE legacy_albums (id bigserial PRIMARY KEY, image_category_id bigint REFERENCES images_categories)"
      )

      [[category_id]] = rows("INSERT INTO images_categories (name) VALUES ('Posts') RETURNING id")

      [[series_id]] =
        rows("INSERT INTO images_series (name, slug, image_category_id) VALUES ('A', 'a', $1) RETURNING id", [
          category_id
        ])

      [[post_id]] = rows("INSERT INTO legacy_posts (image_series_id) VALUES ($1) RETURNING id", [series_id])

      run_template("brando_80_extract_embeds_one_image_fields.exs")

      refute table_exists?("images_series")
      refute table_exists?("images_categories")
      assert rows("SELECT image_series_id FROM legacy_posts") == [[series_id]]

      assert rows("SELECT table_name, entry_id, image_series_id FROM _legacy_image_series_fks") ==
               [["legacy_posts", post_id, series_id]]
    end
  end

  describe "brando_95" do
    test "stops with a clear message when the site has its own videos table" do
      # The test database already has Brando's videos table, standing in for
      # a 0.51 site's own.
      assert table_exists?("videos")

      assert_raise RuntimeError, ~r/already has one.*rename table\(:videos\)/s, fn ->
        run_template("brando_95_extract_videos_embeds_one.exs")
      end
    end
  end

  describe "brando_146" do
    test "numbers gallery objects by (sequence, id), so ties keep one order" do
      {blueprint, field} =
        Enum.find_value(Brando.Blueprint.list_blueprints(), fn blueprint ->
          Enum.find_value(Brando.Blueprint.Assets.__assets__(blueprint), fn
            %{type: :gallery, name: name} -> {blueprint, name}
            _ -> nil
          end)
        end)

      table = blueprint.__schema__(:source)

      # A bare table in the 0.51 shape, with the real one moved aside
      if table_exists?(table), do: query!(~s[ALTER TABLE "#{table}" RENAME TO "#{table}_saved"])
      query!(~s[CREATE TABLE "#{table}" (id bigserial PRIMARY KEY, image_series_id bigint)])

      query!("CREATE TABLE _legacy_image_series (id bigint, name text, slug text, cfg jsonb)")
      query!("CREATE TABLE _legacy_image_series_images (image_id bigint, image_series_id bigint, sequence integer)")
      query!("CREATE TABLE _legacy_image_series_fks (table_name text, entry_id bigint, image_series_id bigint)")

      images = for _ <- 1..4, do: Brando.Factory.insert(:image)
      [a, b, c, d] = Enum.map(images, & &1.id)

      # Two ties on 0, a null, and one ahead of them in insertion order
      for {image_id, sequence} <- [{c, 0}, {a, 0}, {d, nil}, {b, 1}] do
        query!("INSERT INTO _legacy_image_series_images VALUES ($1, 7, $2)", [image_id, sequence])
      end

      [[entry_id]] =
        rows(~s[INSERT INTO "#{table}" (image_series_id) VALUES (7) RETURNING id])

      query!("INSERT INTO _legacy_image_series_fks VALUES ($1, $2, 7)", [table, entry_id])

      run_template("brando_146_migrate_image_series_to_galleries.exs")

      [[gallery_id]] = rows(~s[SELECT "#{field}_id" FROM "#{table}" WHERE id = $1], [entry_id])

      assert rows(
               "SELECT image_id, sequence FROM galleries_gallery_objects WHERE gallery_id = $1 ORDER BY sequence",
               [gallery_id]
             ) == [[a, 0], [c, 1], [d, 2], [b, 3]]
    end
  end

end
