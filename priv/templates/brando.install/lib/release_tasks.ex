defmodule <%= application_module %>.ReleaseTasks do
  @moduledoc ~S"""
  Mix is not available in a built release. Instead we define the tasks here,
  and invoke it using the application script generated in the release:

      bin/<%= application_name %> command Elixir.<%= application_module %>.ReleaseTasks create
      bin/<%= application_name %> command Elixir.<%= application_module %>.ReleaseTasks migrate
      bin/<%= application_name %> command Elixir.<%= application_module %>.ReleaseTasks seed
      bin/<%= application_name %> command Elixir.<%= application_module %>.ReleaseTasks drop
  """

  @otp_app :<%= application_name %>
  @repo <%= application_module %>.Repo

  def create do
    load_app()
    info "Creating database for #{inspect @repo}.."
    case Ecto.Storage.up(@repo) do
      :ok ->
        info "The database for #{inspect @repo} has been created."
      {:error, :already_up} ->
        info "The database for #{inspect @repo} has already been created."
      {:error, term} when is_binary(term) ->
        fatal "The database for #{inspect @repo} couldn't be created, reason given: #{term}."
      {:error, term} ->
        fatal "The database for #{inspect @repo} couldn't be created, reason given: #{inspect term}."
    end
    System.halt(0)
  end

  def drop do
    load_app()
    info "Dropping database for #{inspect @repo}.."
    case Ecto.Storage.down(@repo) do
      :ok ->
        info "The database for #{inspect @repo} has been dropped."
      {:error, :already_down} ->
        info "The database for #{inspect @repo} has already been dropped."
      {:error, term} when is_binary(term) ->
        fatal "The database for #{inspect @repo} couldn't be dropped, reason given: #{term}."
      {:error, term} ->
        fatal "The database for #{inspect @repo} couldn't be dropped, reason given: #{inspect term}."
    end
    System.halt(0)
  end

  def migrate do
    start_repo(@repo)
    migrations_path = Application.app_dir(@otp_app, "priv/@repo/migrations")
    info "Executing migrations for #{inspect @repo} in #{migrations_path}:"
    migrations = Ecto.Migrator.run(@repo, migrations_path, :up, all: true)
    info "Applied versions: #{inspect migrations}"
    System.halt(0)
  end

  def seed do
    start_repo(@repo)
    info "Seeding data for #{inspect @repo}.."
    # Put any needed seeding data here, or maybe run priv/repo/seeds.exs
    System.halt(0)
  end

  defp start_applications(apps) do
    Enum.each(apps, fn app ->
      {:ok, _} = Application.ensure_all_started(app)
    end)
  end

  defp start_repo(repo) do
    load_app()
    {:ok, _} = repo.start_link()
  end

  defp load_app do
    start_applications([:logger, :postgrex, :ecto])
    :ok = Application.load(@otp_app)
  end

  defp info(message) do
    IO.puts(message)
  end

  defp fatal(message) do
    IO.puts :stderr, message
    System.halt(1)
  end
end
