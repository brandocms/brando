defmodule Brando.Repo.Migrations.AddSoftDeletion do
  use Ecto.Migration
  import Brando.SoftDelete.Migration

  def change do
    alter table(:pages_pages) do
      soft_delete()
    end

    alter table(:pages_fragments) do
      soft_delete()
    end

    alter table(:pages_templates) do
      soft_delete()
    end

    alter table(:users_users) do
      soft_delete()
    end

    alter table(:images_categories) do
      soft_delete()
    end

    alter table(:images_series) do
      soft_delete()
    end

    alter table(:images_images) do
      soft_delete()
    end
  end
end
