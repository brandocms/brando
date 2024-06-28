defmodule Brando.Repo.Migrations.ConvertCfgToJSONB do
  use Ecto.Migration

  def change do
    execute """
    ALTER TABLE images_series
      ALTER COLUMN cfg
      SET DATA TYPE jsonb
      USING cfg::jsonb;
    """

    flush()

    execute """
    ALTER TABLE images_categories
      ALTER COLUMN cfg
      SET DATA TYPE jsonb
      USING cfg::jsonb;
    """
  end
end
