defmodule <%= application_module %>.ReleaseTasks do
  @app :<%= application_name %>

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def migrate_tenants do
    load_app()

    for repo <- repos() do
      {:ok, result, _} =
        Ecto.Migrator.with_repo(repo, fn _repo -> Brando.Environments.migrate_all() end)

      {:ok, _migrated} = result
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  # Migrating an empty database logs more than the console handler's burst
  # limit of 500 events a second, and the release halts before the handler
  # reports what it dropped, so the log would stop partway through.
  defp load_app do
    _ = :logger.update_handler_config(:default, :config, %{burst_limit_enable: false})
    Application.load(@app)
  end
end
