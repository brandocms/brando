defmodule Brando.Repo.Migrations.Brando181AddValuesToSeoSuggestions do
  use Ecto.Migration

  @moduledoc """
  A suggestion can carry one text per language: image alt text is written for
  every content language in one request.
  """

  def change do
    alter table(:seo_meta_suggestions) do
      add :values, :map
    end
  end
end
