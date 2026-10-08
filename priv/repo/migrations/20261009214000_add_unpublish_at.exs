defmodule Brando.Repo.Migrations.AddUnpublishAt do
  use Ecto.Migration

  # The expiry `Brando.Trait.ScheduledPublishing` adds beside `publish_at`,
  # on pages, fragments and the e2e Project blueprint.
  def change do
    for table <- [:pages, :pages_fragments, :projects_projects] do
      alter table(table) do
        add :unpublish_at, :utc_datetime
      end

      create index(table, [:unpublish_at])
    end
  end
end
