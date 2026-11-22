defmodule Brando.Migrations.Brando244AddFragmentAlternatesTest do
  # Two histories reach brando_244: an installation that ran brando_93 before
  # fragments had language links has no table for them, and one that runs
  # brando_93 with this version of Brando gets the table from it. Both end
  # with the table the test schema has, constraints included.
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_244_add_fragment_alternates.exs"
  @replayed "tenant_acme_staging"
  @earlier "tenant_acme_production"
  @table "pages_fragments_alternates"

  # brando_93 and brando_96 run in `public` only, against every table of
  # the application's Blueprints and Brando's Page and Fragment there. Run
  # with `prefix` alone on the search path, for an application with no
  # Blueprints of its own (here Brando is the application, whose Blueprints
  # are Page and Fragment again), they see that environment's fragments table
  # and nothing else.
  defp replay_in(prefix, files) do
    app = :brando_244_site

    :ok =
      :application.load(
        {:application, app, [description: ~c"site", vsn: ~c"0.0.0", modules: [], registered: [], applications: []]}
      )

    on_exit(fn -> :application.unload(app) end)
    put_test_env(:otp_app, app)

    [[search_path]] = rows("SHOW search_path")
    query!(~s(SET LOCAL search_path TO "#{prefix}"))

    try do
      Enum.each(files, &up/1)
    after
      query!("SELECT set_config('search_path', $1, true)", [search_path])
    end
  end

  # The test schema's table, its foreign keys pointing into `prefix`
  defp expected(prefix) do
    {columns, indexes, references} = table_set("public", [@table])[@table]
    {columns, indexes, Enum.map(references, fn {column, "public", target} -> {column, prefix, target} end)}
  end

  defp fragment!(prefix, language) do
    [[id]] =
      rows(
        ~s{INSERT INTO "#{prefix}".pages_fragments (parent_key, key, language, inserted_at, updated_at)
           VALUES ('footer', 'contact', $1, now(), now()) RETURNING id},
        [language]
      )

    id
  end

  test "creates the table where brando_93 did not, and leaves the one it made" do
    create_environment(@replayed, ["pages_fragments"])
    create_environment(@earlier, ["pages_fragments"])

    # brando_93 run with this version: fragments have language links
    replay_in(@replayed, [
      "brando_93_add_translatable_alternates_tables.exs",
      "brando_96_change_translatable_alternates_constraints.exs"
    ])

    assert table?(@replayed, @table)
    refute table?(@earlier, @table)

    no = fragment!(@replayed, "no")
    en = fragment!(@replayed, "en")

    query!(
      ~s{INSERT INTO "#{@replayed}".#{@table} (entry_id, linked_entry_id, inserted_at, updated_at) VALUES ($1, $2, now(), now())},
      [no, en]
    )

    up(@template)

    for prefix <- [@replayed, @earlier] do
      assert table_set(prefix, [@table])[@table] == expected(prefix)
    end

    assert rows(~s{SELECT entry_id, linked_entry_id FROM "#{@replayed}".#{@table}}, []) == [[no, en]]

    # Reciprocal uniqueness, and the links go with their fragment
    no = fragment!(@earlier, "no")
    en = fragment!(@earlier, "en")

    insert =
      ~s{INSERT INTO "#{@earlier}".#{@table} (entry_id, linked_entry_id, inserted_at, updated_at) VALUES ($1, $2, now(), now())}

    query!(insert, [no, en])
    query!(insert, [en, no])

    assert_raise Postgrex.Error, ~r/unique/, fn ->
      BrandoIntegration.Repo.transaction(fn -> query!(insert, [no, en]) end)
    end

    query!(~s{DELETE FROM "#{@earlier}".pages_fragments WHERE id = $1}, [en])
    assert rows(~s{SELECT count(*) FROM "#{@earlier}".#{@table}}, []) == [[0]]
  end

  test "leaves an environment without fragments alone" do
    create_environment(@earlier)
    up(@template)
    refute table?(@earlier, @table)
  end
end
