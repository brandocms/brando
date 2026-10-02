defmodule Brando.Repo.Migrations.Brando193AddForms do
  use Ecto.Migration

  @moduledoc """
  Front-end forms (`Brando.Forms.Form`) and their fields, in every site
  environment.
  """

  def up do
    Enum.each(prefixes(), &Brando.Forms.Migration.content_up/1)
  end

  def down do
    Enum.each(prefixes(), &Brando.Forms.Migration.content_down/1)
  end

  defp prefixes do
    %{rows: rows} =
      repo().query!(
        "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
      )

    Enum.map(rows, &hd/1)
  end
end
