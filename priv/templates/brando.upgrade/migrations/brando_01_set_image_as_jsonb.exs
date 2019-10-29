defmodule Brando.Repo.Migrations.ConvertImagesToJSONB do
  use Ecto.Migration

  def change do
    execute """
    alter table images alter column image type jsonb using image::JSON
    """

    flush()

    execute """
    alter table users alter column avatar type jsonb using avatar::JSON
    """

    <%= Brando.Field.ImageField.generate_image_fields_migration() %>
  end
end
