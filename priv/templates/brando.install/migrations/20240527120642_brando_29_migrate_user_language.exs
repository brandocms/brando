defmodule Brando.Migrations.MigrateUserLanguage do
  use Ecto.Migration
  import Ecto.Query

  def change do
    query = from(t in "users_users", where: t.language == "nb", update: [set: [language: "no"]])
    Brando.repo().update_all(query, [])
    flush()
  end
end
