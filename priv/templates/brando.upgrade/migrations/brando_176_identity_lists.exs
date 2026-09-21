defmodule Brando.Migrations.IdentityLists do
  use Ecto.Migration

  # area_served and knows_about used to be comma-separated strings inside the
  # type_config jsonb. Brando.Type.StringList still loads the old shape, so
  # this only rewrites stored rows to the list form.
  @fields ~w(area_served knows_about)

  def up do
    for field <- @fields do
      execute """
      UPDATE sites_identities
      SET type_config = jsonb_set(
        type_config,
        '{#{field}}',
        COALESCE(
          (
            SELECT to_jsonb(array_remove(array_agg(trim(part)), ''))
            FROM unnest(string_to_array(type_config->>'#{field}', ',')) AS part
          ),
          '[]'::jsonb
        )
      )
      WHERE type_config IS NOT NULL
        AND jsonb_typeof(type_config->'#{field}') = 'string'
      """
    end
  end

  def down do
    for field <- @fields do
      execute """
      UPDATE sites_identities
      SET type_config = jsonb_set(
        type_config,
        '{#{field}}',
        to_jsonb(array_to_string(ARRAY(SELECT jsonb_array_elements_text(type_config->'#{field}')), ', '))
      )
      WHERE type_config IS NOT NULL
        AND jsonb_typeof(type_config->'#{field}') = 'array'
      """
    end
  end
end
