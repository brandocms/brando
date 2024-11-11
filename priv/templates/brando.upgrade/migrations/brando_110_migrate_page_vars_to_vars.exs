defmodule Brando.Repo.Migrations.MigratePageVarsToVars do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # pages has embeds_many :vars. transfer these to content_vars and set page_id
    query =
      from(g in "pages",
        select: %{
          id: g.id,
          creator_id: g.creator_id,
          vars: g.vars
        }
      )

    pages = Brando.Repo.all(query)

    for page <- pages do
      process_vars(page.id, page.creator_id, page.vars || [])
    end

    alter table(:pages) do
      remove :vars
    end
  end

  def down do
    alter table(:pages) do
      add :vars, :jsonb
    end
  end

  defp process_vars(page_id, creator_id, vars) do
    for var <- vars do
      base_var = build_var(var, page_id, creator_id)

      new_var =
        case var do
          %{"type" => "color"} ->
            Map.merge(base_var, %{
              value: get_in(var, ["value"]),
              color_picker: get_in(var, ["picker"]),
              color_opacity: get_in(var, ["opacity"]),
              palette_id: get_in(var, ["palette_id"])
            })

          %{"type" => "image"} ->
            Map.merge(base_var, %{
              image_id: get_in(var, ["value_id"])
            })

          %{"type" => "file"} ->
            Map.merge(base_var, %{
              file_id: get_in(var, ["value_id"])
            })

          %{"type" => "boolean"} ->
            Map.merge(base_var, %{
              value_boolean: get_in(var, ["value"])
            })

          %{"type" => "select"} ->
            Map.merge(base_var, %{
              value: get_in(var, ["value"]),
              options: get_in(var, ["options"])
            })

          _ ->
            Map.merge(base_var, %{
              value: get_in(var, ["value"])
            })
        end

      new_var =
        Map.merge(new_var, %{
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        })

      Brando.Repo.insert_all("content_vars", [new_var])
    end
  end

  def build_var(var, page_id, creator_id) do
    %{
      type: get_in(var, ["type"]),
      important: get_in(var, ["important"]),
      instructions: get_in(var, ["instructions"]),
      key: get_in(var, ["key"]),
      label: get_in(var, ["label"]),
      placeholder: get_in(var, ["placeholder"]),
      page_id: page_id,
      creator_id: creator_id
    }
  end
end
