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

  setup do
    directory = Path.join(System.tmp_dir!(), "brando_upgrade_#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    %{directory: directory, files: directory |> copy_2xx() |> Enum.map(&elem(&1, 1))}
  end

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

  defp page(prefix, id), do: rows(~s(SELECT title, content_modified_at FROM "#{prefix}".pages WHERE id = $1), [id])
  defp module_code(prefix, id), do: rows(~s(SELECT code FROM "#{prefix}".content_modules WHERE id = $1), [id])

  test "the brando_2xx migrations upgrade environments that already hold content, and roll back", %{
    directory: directory,
    files: files
  } do
    # Reserved and never used; the upgrade runs across the gaps
    numbers = Enum.map(files, &number/1)
    assert Enum.to_list(200..213) -- numbers == [206, 208]

    expected_tables = table_set("public", environment_tables())
    expected_columns = column_set("public", environment_columns())
    expected_public = {table_set("public", public_tables()), column_set("public", public_columns())}

    roll_back_2xx()
    content = Map.new(@environments, &{&1, provision(&1)})

    assert length(migrate(directory, :up)) == length(files)

    assert {table_set("public", public_tables()), column_set("public", public_columns())} == expected_public
    assert table_set("public", environment_tables()) == expected_tables
    assert column_set("public", environment_columns()) == expected_columns

    for prefix <- @environments do
      %{page: page_id, module: module_id} = content[prefix]

      assert table_set(prefix, environment_tables()) == in_environment(expected_tables, prefix)
      assert column_set(prefix, environment_columns()) == expected_columns
      assert MapSet.disjoint?(MapSet.new(tables(prefix)), MapSet.new(public_tables() ++ Map.keys(public_columns())))

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
    assert environment_tables() -- cloned == []
    assert Enum.filter(public_tables(), &(&1 in cloned)) == []
    assert Enum.all?(public_tables(), &SharedTables.member?/1)

    assert length(migrate(directory, :down)) == length(files)

    for prefix <- ["public" | @environments] do
      for table <- environment_tables(), do: refute(table?(prefix, table))
      assert column_set(prefix, environment_columns()) == Map.new(environment_columns(), fn {table, _} -> {table, []} end)
    end

    for table <- public_tables(), do: refute(table?("public", table))
    assert column_set("public", public_columns()) == Map.new(public_columns(), fn {table, _} -> {table, []} end)

    for prefix <- @environments do
      %{page: page_id} = content[prefix]
      assert [["About " <> _]] = rows(~s(SELECT title FROM "#{prefix}".pages WHERE id = $1), [page_id])
    end
  end
end
