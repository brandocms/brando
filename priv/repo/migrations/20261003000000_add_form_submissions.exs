defmodule BrandoIntegration.Repo.Migrations.AddFormSubmissions do
  use Ecto.Migration

  @moduledoc "Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_194_add_form_submissions.exs`."

  def up do
    Brando.Forms.Migration.shared_up()
    Brando.Forms.Migration.vars_up()
  end

  def down do
    Brando.Forms.Migration.vars_down()
    Brando.Forms.Migration.shared_down()
  end
end
