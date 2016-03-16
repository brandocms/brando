defmodule <%= application_module %>.ReleaseTasks do
  @moduledoc ~S"""
  Mix is not available in a built release. Instead we define the tasks here and use a small escript
  that delegates to `<%= application_module %>.ReleaseTasks.main`. See `ReleaseManager.Plugin.ReleaseTasks`.
  In the release you can invoke tasks like this:
      bin/marit_larsen escript bin/release_tasks.escript migrate
  """

  @otp_app :<%= application_name %>

  def main(args) do
    start_applications([:elixir])
    run_task(args)
  end

  defp run_task(['migrate']), do: migrate()
  defp run_task(['seed'|args]), do: seed(args)

  def migrate do
    start_repo()
    migrations_path = Application.app_dir(@otp_app, "priv/migrations")
    Ecto.Migrator.run(<%= application_module %>.Repo, migrations_path, :up, all: true)
  end

  defp seed(args) do
    start_repo()
    # <%= application_module %>.Repo.insert(...)
  end

  defp start_applications(apps) do
    Enum.each(apps, fn app ->
      {:ok, _} = Application.ensure_all_started(app)
    end)
  end

  defp start_repo do
    start_applications([:logger, :postgrex, :ecto])
    :ok = Application.load(@otp_app)
    {:ok, _} = <%= application_module %>.Repo.start_link()
  end

  defp fatal(message) do
    IO.puts :stderr, message
    System.halt(1)
  end
end
