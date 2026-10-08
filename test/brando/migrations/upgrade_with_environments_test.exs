defmodule Brando.Migrations.UpgradeWithEnvironmentsTest do
  # A database from before the brando_2xx migrations, with two environment
  # schemas holding content, upgraded the way an application does it:
  # `mix brando.gen.migrations` copies the templates under the versions the
  # installer gives them, and `mix brando.migrate` runs the directory. Then
  # everything is rolled back again.
  #
  # Runs inside the sandbox transaction; Postgres DDL is transactional, so the
  # tables dropped to get the "before" state, the environment schemas and the
  # migrations are all undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  alias Brando.Environments.StructureCloner
  alias Brando.Tenant.SharedTables

  # The second key has a hyphen, which site and environment keys allow
  @environments ["tenant_acme_staging", "tenant_acme-shop_production"]

  # What the 2xx migrations add in every environment
  @environment_tables ~w(sites_not_found_hits entry_notes note_mentions webhooks webhook_deliveries sites_indexnow
                         search_documents)
  @environment_columns %{
    "pages" => ~w(meta_canonical_url content_modified_at meta_nosnippet meta_max_snippet),
    "sites_seos" => ~w(crawler_policy),
    "content_modules" => ~w(markdown_code)
  }

  # ...and in `public` only
  @public_tables ~w(users_security users_recovery_codes users_security_events users_security_policy users_passkeys
                    mcp_settings mcp_grants mcp_tokens mcp_authorization_codes)
  @public_columns %{
    "users" => ~w(job_title same_as),
    "users_tokens" => ~w(ip user_agent last_used_at confirmed_at),
    "content_proposals" => ~w(origin client)
  }

  # The schemas that read the environment tables the 2xx migrations change
  @environment_schemas [
    Brando.Pages.Page,
    Brando.Content.Module,
    Brando.Sites.SEO,
    Brando.Sites.NotFoundHit,
    Brando.Notes.Note,
    Brando.Notes.Mention,
    Brando.Webhooks.Webhook,
    Brando.Webhooks.Delivery,
    Brando.IndexNow.Settings,
    Brando.Search.Document
  ]

  @gallery_loop """
  {% assign images = refs.slider.gallery.gallery_objects %}
  {% for image in images %}{% picture image %}{% endfor %}
  """

  setup do
    directory = Path.join(System.tmp_dir!(), "brando_upgrade_#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    # The files and versions `mix brando.gen.migrations` would copy
    files =
      for {_format, "../brando.upgrade/migrations/" <> file, target} <- Mix.Brando.Install.Templates.manifest(),
          file =~ ~r/^brando_2\d\d_/ do
        File.cp!(path(file), Path.join(directory, Path.basename(target)))
        file
      end

    %{directory: directory, files: files}
  end

  # Runs the directory as `mix brando.migrate` does, then unloads the
  # migration modules so the next run compiles them afresh
  defp migrate(directory, direction) do
    versions =
      Ecto.Migrator.run(BrandoIntegration.Repo, [directory], direction, all: true, log: false, migration_lock: false)

    for file <- Path.wildcard(Path.join(directory, "*.exs")),
        [_, module] <- [Regex.run(~r/defmodule (\S+) do/, File.read!(file))] do
      module = Module.concat([module])
      :code.purge(module)
      :code.delete(module)
    end

    versions
  end

  defp column_set(schema, columns) do
    for {table, names} <- columns,
        do: {table, schema |> column_definitions(table) |> Enum.filter(&(elem(&1, 0) in names))},
        into: %{}
  end

  defp table_set(schema, tables),
    do: Map.new(tables, &{&1, {column_definitions(schema, &1), indexes(schema, &1), references(schema, &1)}})

  # Foreign keys to the environment's own tables name the environment; the
  # ones to users name `public`
  defp in_environment(table_set, schema) do
    Map.new(table_set, fn {table, {columns, indexes, references}} ->
      references =
        Enum.map(references, fn
          {column, "public", "users"} -> {column, "public", "users"}
          {column, "public", target} -> {column, schema, target}
        end)

      {table, {columns, indexes, Enum.sort(references)}}
    end)
  end

  # Rolls `public` back to before the 2xx migrations
  defp roll_back_public do
    query!("DROP TABLE #{Enum.join(@environment_tables ++ @public_tables, ", ")}")

    for {table, names} <- Map.merge(@environment_columns, @public_columns) do
      query!(~s(ALTER TABLE "#{table}" ) <> Enum.map_join(names, ", ", &"DROP COLUMN #{&1}"))
    end
  end

  # An environment as provisioning makes it: every non-shared table of public
  defp provision(prefix) do
    {:ok, tables} = StructureCloner.Postgres.tenant_tables("public")
    create_environment(prefix, tables)

    [[page_id]] =
      rows("""
      INSERT INTO "#{prefix}".pages (uri, language, title, template, edited_at, inserted_at, updated_at)
      VALUES ('about', 'en', 'About #{prefix}', 'default.html', '2026-01-01 10:00:00', '2025-01-01 10:00:00', '2026-05-01 10:00:00')
      RETURNING id
      """)

    [[module_id]] =
      rows(
        """
        INSERT INTO "#{prefix}".content_modules (uid, class, code, inserted_at, updated_at)
        VALUES ($1, 'slider', $2, NOW(), NOW()) RETURNING id
        """,
        [Brando.Utils.generate_uid(), @gallery_loop]
      )

    %{page: page_id, module: module_id}
  end

  defp page(prefix, id), do: rows(~s(SELECT title, content_modified_at FROM "#{prefix}".pages WHERE id = $1), [id])
  defp module_code(prefix, id), do: rows(~s(SELECT code FROM "#{prefix}".content_modules WHERE id = $1), [id])

  test "the brando_2xx migrations upgrade environments that already hold content, and roll back", %{
    directory: directory,
    files: files
  } do
    # Reserved and never used; the upgrade runs across the gaps
    numbers = Enum.map(files, &number/1)
    assert Enum.to_list(200..213) -- numbers == [206, 208]

    expected_tables = table_set("public", @environment_tables)
    expected_columns = column_set("public", @environment_columns)
    expected_public = {table_set("public", @public_tables), column_set("public", @public_columns)}

    roll_back_public()
    content = Map.new(@environments, &{&1, provision(&1)})

    assert length(migrate(directory, :up)) == length(files)

    assert {table_set("public", @public_tables), column_set("public", @public_columns)} == expected_public
    assert table_set("public", @environment_tables) == expected_tables
    assert column_set("public", @environment_columns) == expected_columns

    for prefix <- @environments do
      %{page: page_id, module: module_id} = content[prefix]

      assert table_set(prefix, @environment_tables) == in_environment(expected_tables, prefix)
      assert column_set(prefix, @environment_columns) == expected_columns
      assert MapSet.disjoint?(MapSet.new(tables(prefix)), MapSet.new(@public_tables ++ Map.keys(@public_columns)))

      # The content is still there, and the data migrations ran on it
      assert page(prefix, page_id) == [["About #{prefix}", ~N[2026-01-01 10:00:00]]]
      assert [[code]] = module_code(prefix, module_id)
      assert code =~ "{% picture image.image %}"

      for schema <- @environment_schemas do
        assert is_list(BrandoIntegration.Repo.all(schema, prefix: prefix))
      end
    end

    # An environment provisioned after the upgrade gets the new environment
    # tables, and none of the public ones
    {:ok, cloned} = StructureCloner.Postgres.tenant_tables("public")
    assert @environment_tables -- cloned == []
    assert Enum.filter(@public_tables, &(&1 in cloned)) == []
    assert Enum.all?(@public_tables, &SharedTables.member?/1)

    assert length(migrate(directory, :down)) == length(files)

    for prefix <- ["public" | @environments] do
      for table <- @environment_tables, do: refute(table?(prefix, table))
      assert column_set(prefix, @environment_columns) == Map.new(@environment_columns, fn {table, _} -> {table, []} end)
    end

    for table <- @public_tables, do: refute(table?("public", table))
    assert column_set("public", @public_columns) == Map.new(@public_columns, fn {table, _} -> {table, []} end)

    for prefix <- @environments do
      %{page: page_id} = content[prefix]
      assert [["About " <> _]] = rows(~s(SELECT title FROM "#{prefix}".pages WHERE id = $1), [page_id])
    end
  end
end
