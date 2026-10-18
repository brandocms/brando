# Migrates a new, empty database from scratch, as a new server, CI or a new
# test database does, then drops it:
#
#   mix run --no-start fresh_migrations.exs
#
# There Brando's upgrade migrations run before the consumer's own migrations
# have created its Blueprints' tables, so a migration that acts on a table it
# finds through current code must skip what is not there yet.
{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Application.ensure_all_started(:postgrex)

repo = IgniterSmoke.Repo
config = Application.fetch_env!(:igniter_smoke, repo)
database = Keyword.fetch!(config, :database) <> "_fresh"
true = String.starts_with?(database, "brando_igniter_smoke_")
Application.put_env(:igniter_smoke, repo, Keyword.put(config, :database, database))
adapter = repo.__adapter__()

case adapter.storage_down(repo.config()) do
  :ok -> :ok
  {:error, :already_down} -> :ok
end

:ok = adapter.storage_up(repo.config())

try do
  {:ok, pending, _apps} =
    Ecto.Migrator.with_repo(repo, fn repo ->
      Ecto.Migrator.run(repo, :up, all: true)
      for {:down, version, name} <- Ecto.Migrator.migrations(repo), do: {version, name}
    end)

  if pending != [], do: raise("Migrations left pending in #{database}: #{inspect(pending)}")
  IO.puts("Migrated #{database} from scratch")
after
  adapter.storage_down(repo.config())
end
