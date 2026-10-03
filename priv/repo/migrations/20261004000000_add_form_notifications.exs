defmodule BrandoIntegration.Repo.Migrations.AddFormNotifications do
  use Ecto.Migration

  @moduledoc "Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_196_add_form_notifications.exs`."

  def up do
    Brando.Forms.Migration.settings_up()
    Brando.Forms.Migration.shared_status_up()
  end

  def down do
    Brando.Forms.Migration.shared_status_down()
    Brando.Forms.Migration.settings_down()
  end
end
