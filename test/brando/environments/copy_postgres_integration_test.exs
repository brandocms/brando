defmodule Brando.Environments.CopyPostgresIntegrationTest do
  use ExUnit.Case, async: false

  alias Brando.Environments
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  defmodule Repo do
    use Ecto.Repo,
      otp_app: :brando,
      adapter: Ecto.Adapters.Postgres
  end

  setup_all do
    integration_config = BrandoIntegration.Repo.config()

    repo_options =
      integration_config
      |> Keyword.take([:database, :hostname, :password, :port, :socket_options, :ssl, :username])
      |> Keyword.merge(pool: DBConnection.ConnectionPool, pool_size: 3)

    previous_repo_config = Application.fetch_env(:brando, Repo)
    Application.put_env(:brando, Repo, repo_options)
    {:ok, repo} = Repo.start_link()

    on_exit(fn ->
      try do
        GenServer.stop(repo)
      catch
        :exit, _ -> :ok
      end

      restore_env(Repo, previous_repo_config)
    end)

    :ok
  end

  setup do
    previous_repo = Application.fetch_env(:brando, :repo_module)
    previous_cloner = Application.fetch_env(:brando, :environment_schema_cloner)
    Application.put_env(:brando, :repo_module, Repo)
    Application.delete_env(:brando, :environment_schema_cloner)

    unique = System.unique_integer([:positive])
    site_key = "copyint#{unique}"

    %{rows: [[site_id]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        INSERT INTO public.sites
          (name, key, languages, default_language, status, delivery_mode, deploy_config, inserted_at, updated_at)
        VALUES
          ('Copy integration', $1, ARRAY['en'], 'en', 'active', 'dynamic', '{}'::jsonb, NOW(), NOW())
        RETURNING id
        """,
        [site_key]
      )

    for {name, key, live} <- [{"Source", "source", true}, {"Target", "target", false}] do
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        INSERT INTO public.environments
          (site_id, name, key, live, inserted_at, updated_at)
        VALUES
          ($1, $2, $3, $4, NOW(), NOW())
        """,
        [site_id, name, key, live]
      )
    end

    source_prefix = "tenant_#{site_key}_source"
    target_prefix = "tenant_#{site_key}_target"

    create_records_schema(source_prefix, ["source-one", "source-two"])
    create_records_schema(target_prefix, ["old-target"])
    Cache.clear()

    on_exit(fn ->
      drop_site_schemas(site_key)
      Ecto.Adapters.SQL.query!(Repo, "DELETE FROM public.sites WHERE id = $1", [site_id])
      restore_env(:repo_module, previous_repo)
      restore_env(:environment_schema_cloner, previous_cloner)
      Cache.clear()
    end)

    %{site_id: site_id, source_prefix: source_prefix, target_prefix: target_prefix}
  end

  test "copies through committed DDL while holding the site advisory lock", context do
    site = Registry.get_site(context.site_id)
    source = Registry.get_environment_by_key(site, "source")
    target = Registry.get_environment_by_key(site, "target")

    assert {:ok, %{archive_schema: archive_schema}} =
             Environments.copy_environment(source, target)

    assert %{rows: [["source-one"], ["source-two"]]} =
             records_in(context.target_prefix)

    assert %{rows: [["old-target"]]} = records_in(archive_schema)
  end

  defp create_records_schema(prefix, names) do
    Ecto.Adapters.SQL.query!(Repo, ~s|CREATE SCHEMA "#{prefix}"|, [])

    Ecto.Adapters.SQL.query!(
      Repo,
      ~s|CREATE TABLE "#{prefix}".records (id serial PRIMARY KEY, name text NOT NULL)|,
      []
    )

    Enum.each(names, fn name ->
      Ecto.Adapters.SQL.query!(
        Repo,
        ~s|INSERT INTO "#{prefix}".records (name) VALUES ($1)|,
        [name]
      )
    end)
  end

  defp records_in(prefix) do
    Ecto.Adapters.SQL.query!(
      Repo,
      ~s|SELECT name FROM "#{prefix}".records ORDER BY id|,
      []
    )
  end

  defp drop_site_schemas(site_key) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT nspname FROM pg_namespace WHERE nspname LIKE $1",
        ["tenant_#{site_key}_%"]
      )

    Enum.each(rows, fn [schema] ->
      Ecto.Adapters.SQL.query!(Repo, ~s|DROP SCHEMA "#{schema}" CASCADE|, [])
    end)
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:brando, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:brando, key)
end
