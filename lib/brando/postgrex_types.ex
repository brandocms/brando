Postgrex.Types.define(
  Brando.PostgresTypes,
  [Postgrex.Extensions.JSON] ++ Ecto.Adapters.Postgres.extensions(),
  json: Poison
)
