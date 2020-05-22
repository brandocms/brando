defmodule Brando.Migrations.ExtractGlobals do
  use Ecto.Migration
  import Ecto.Query

  def change do
    # create categories
    create table(:sites_global_categories) do
      add :key, :string
      add :label, :text
    end

    create table(:sites_globals) do
      add :key, :string
      add :label, :text
      add :type, :string
      add :data, :jsonb
      add :global_category_id, references(:sites_global_categories, on_delete: :delete_all)
    end

    flush()

    [categories] =
      from(t in "sites_identities",
        select: t.global_categories,
        limit: 1
      )
      |> Brando.repo().all()

    new_categories_data =
      Enum.map(categories, fn c ->
        [
          key: Map.get(c, "key"),
          label: Map.get(c, "label")
        ]
      end)

    Brando.repo().insert_all("sites_global_categories", new_categories_data)

    flush()

    new_categories =
      from(t in "sites_global_categories", select: %{id: t.id, key: t.key})
      |> Brando.repo().all()

    entries =
      Enum.flat_map(categories, fn c ->
        Enum.map(Map.get(c, "globals"), fn g ->
          [
            type: "text",
            key: Map.get(g, "key"),
            label: Map.get(g, "label"),
            data: %{value: Map.get(g, "value")},
            category_id: Enum.find(new_categories, &(&1.key == Map.get(c, "key"))).id
          ]
        end)
      end)

    flush()

    alter table(:sites_identities) do
      remove :global_categories
    end
  end
end
