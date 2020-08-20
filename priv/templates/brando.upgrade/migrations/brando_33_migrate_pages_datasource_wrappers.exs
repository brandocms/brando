defmodule Brando.Migrations.MigrateDatasourceWrappers do
  use Ecto.Migration
  import Ecto.Query

  def change do
    tbls = ["pages_fragments", "pages_pages"]

    for tbl <- tbls do
      query = """
      SELECT
        id,
        root_blocks->'data'->'wrapper' as wrapper,
        root_blocks->'data'->'template' as template_id
      FROM
        (SELECT
          id,
          jsonb_array_elements(data::jsonb) AS root_blocks
        FROM
          #{tbl}) root_q
      WHERE
        root_blocks->>'type' = 'datasource'
      """

      {:ok, %{rows: rows}} = Ecto.Adapters.SQL.query(Brando.repo(), query, [])

      for [id, wrapper, template_id] <- rows do
        if wrapper do
          wrapper = String.replace(wrapper, "${CONTENT}", "${content}")

          query =
            from(t in "pages_templates",
              where: t.id == ^template_id,
              update: [set: [wrapper: ^wrapper]]
            )

          Brando.repo().update_all(query, [])
        end
      end
    end
  end
end
