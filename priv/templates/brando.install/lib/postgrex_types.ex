Postgrex.Types.define(<%= application_module %>.PostgresTypes,
                      [Postgrex.Extensions.JSON] ++ Ecto.Adapters.Postgres.extensions(), json: Poison)
