defmodule Brando.Test.Committed do
  @moduledoc """
  Gives synchronous multi-connection tests a private PostgreSQL database.
  Migrate a template once in `setup_all`, then start a fresh copy for each
  test. The main repo stays in manual sandbox mode throughout.
  """

  alias Brando.Test.Support
  alias Ecto.Adapters.Postgres
  import ExUnit.Callbacks, only: [on_exit: 1, start_supervised!: 1, stop_supervised!: 1]

  defmodule Repo do
    @moduledoc false
    use Ecto.Repo, otp_app: :brando, adapter: Ecto.Adapters.Postgres
    use Brando.SoftDelete.Repo
  end

  def template do
    config = create_database!([])
    start_supervised!({Repo, config})
    Brando.MigrationTemplates.migrate(Application.app_dir(:brando, "priv/repo/migrations"), :up, Repo)
    stop_supervised!(Repo)
    %{template: config[:database]}
  end

  def start(template) do
    config = create_database!(template: template)
    Support.put_test_env(Repo, config)
    start_supervised!(Repo)
    Support.put_test_env(:repo_module, Repo)
    Code.eval_file("priv/repo/seeds.exs")
    :ok
  end

  # Oban is started once for the suite. Its inserts and user queries must
  # reach the same database, including in processes the renderer starts.
  def oban_repo do
    if Brando.repo() == Repo, do: Repo, else: BrandoIntegration.Repo.get_dynamic_repo()
  end

  defp create_database!(opts) do
    name = "brando_test_committed_" <> Base.encode16(:crypto.strong_rand_bytes(10), case: :lower)

    config =
      BrandoIntegration.Repo.config()
      |> Keyword.drop([:url, :ownership_pool, :pool_overflow, :name])
      |> Keyword.merge(database: name, pool: DBConnection.ConnectionPool)

    :ok = Postgres.storage_up(Keyword.merge(config, opts))
    on_exit(fn -> :ok = Postgres.storage_down(Keyword.put(config, :force_drop, true)) end)
    config
  end
end
