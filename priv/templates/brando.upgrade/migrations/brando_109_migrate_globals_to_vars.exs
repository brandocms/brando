defmodule Brando.Repo.Migrations.MigrateGlobalsToVars do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # sites_global_sets has embeds_many :globals. transfer these to content_vars and set global_set_id
    query = from g in "sites_global_sets", select: %{
      id: g.id,
      creator_id: g.creator_id,
      globals: g.globals
    }

    global_sets = Brando.Repo.all(query)

    for global_set <- global_sets do
      process_vars(global_set.id, global_set.creator_id, global_set.globals)
    end

    alter table(:sites_global_sets) do
      remove :globals
    end
  end

  def down do
    alter table(:sites_global_sets) do
      add :globals, :jsonb
    end
  end

  defp process_vars(global_set_id, creator_id, vars) do
    for var <- vars do
      base_var = build_var(var, global_set_id, creator_id)
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

  def build_var(var, global_set_id, creator_id) do
    %{
      type: get_in(var, ["type"]),
      important: get_in(var, ["important"]),
      instructions: get_in(var, ["instructions"]),
      key: get_in(var, ["key"]),
      label: get_in(var, ["label"]),
      placeholder: get_in(var, ["placeholder"]),
      global_set_id: global_set_id,
      creator_id: creator_id
    }
  end
end
