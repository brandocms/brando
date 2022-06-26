defmodule Brando.Migrations.SetUserConfigChangePasswordFalse do
  use Ecto.Migration
  import Ecto.Query

  def change do
    query = from u in "users",
      select: u.id,
      update: [set: [config: fragment("jsonb_set(config, '{reset_password_on_first_login}', 'false')")]]

    Brando.repo.update_all(query, [])
  end
end
