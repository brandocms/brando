defmodule Brando.Repo.Migrations.Brando196AddFormNotifications do
  use Ecto.Migration

  @moduledoc """
  A form's recipients, email subject, visitor confirmation, redirect and
  retention (`Brando.Forms.Form`) in every site environment, and whether each
  submission's notification was sent (`Brando.Forms.Submission`).
  """

  def up do
    Enum.each(prefixes(), &Brando.Forms.Migration.settings_up/1)
    Brando.Forms.Migration.shared_status_up()
  end

  def down do
    Brando.Forms.Migration.shared_status_down()
    Enum.each(prefixes(), &Brando.Forms.Migration.settings_down/1)
  end

  defp prefixes do
    %{rows: rows} =
      repo().query!(
        "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
      )

    Enum.map(rows, &hd/1)
  end
end
