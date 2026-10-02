defmodule Brando.Repo.Migrations.Brando194AddFormSubmissions do
  use Ecto.Migration

  @moduledoc """
  Form submissions (`Brando.Forms.Submission`), shared by every site
  environment, and the `form_id` of a block var holding a form.
  """

  def up do
    Brando.Forms.Migration.shared_up()
    Enum.each(prefixes(), &Brando.Forms.Migration.vars_up/1)
  end

  def down do
    Enum.each(prefixes(), &Brando.Forms.Migration.vars_down/1)
    Brando.Forms.Migration.shared_down()
  end

  defp prefixes do
    %{rows: rows} =
      repo().query!(
        "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
      )

    Enum.map(rows, &hd/1)
  end
end
