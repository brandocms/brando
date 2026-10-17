# The consumer's database as seeded, for a second browser pass:
#
#   mix run --no-start database.exs snapshot   copies it to <database>_seeded
#   mix run --no-start database.exs restore    replaces it with that copy
#
# Both need the consumer's server stopped: PostgreSQL copies a database only
# while nothing is connected to it.
[command] = System.argv()
{:ok, _} = Application.ensure_all_started(:postgrex)

config = Application.fetch_env!(:igniter_smoke, IgniterSmoke.Repo)
database = Keyword.fetch!(config, :database)
true = String.starts_with?(database, "brando_igniter_smoke_")
snapshot = database <> "_seeded"

{:ok, conn} =
  config
  |> Keyword.take([:hostname, :port, :username, :password])
  |> Keyword.put(:database, "postgres")
  |> Postgrex.start_link()

statements =
  case command do
    "snapshot" ->
      [~s(CREATE DATABASE "#{snapshot}" TEMPLATE "#{database}")]

    "restore" ->
      [
        ~s(DROP DATABASE "#{database}"),
        ~s(CREATE DATABASE "#{database}" TEMPLATE "#{snapshot}"),
        ~s(DROP DATABASE "#{snapshot}")
      ]
  end

Enum.each(statements, &Postgrex.query!(conn, &1, []))
IO.puts("#{command}: #{database}")
