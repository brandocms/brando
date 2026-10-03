defmodule BrandoIntegration.Repo.Migrations.AddForms do
  use Ecto.Migration

  @moduledoc "Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_194_add_forms.exs`."

  def up, do: Brando.Forms.Migration.content_up()
  def down, do: Brando.Forms.Migration.content_down()
end
