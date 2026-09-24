defmodule Brando.Repo.Migrations.Brando181AddValuesToSeoSuggestions do
  use Ecto.Migration

  @moduledoc """
  Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_181_*`.
  """

  def change do
    alter table(:seo_meta_suggestions) do
      add :values, :map
    end
  end
end
