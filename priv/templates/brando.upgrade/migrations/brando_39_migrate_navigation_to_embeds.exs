defmodule Brando.Migrations.MigrateNavigationToEmbeds do
  use Ecto.Migration
  import Ecto.Query

  def change do
    alter table(:navigation_menus) do
      add :items, :map
    end

    flush()

    Brando.repo().transaction(fn ->
      q =
        from(t in "navigation_menus",
          select: t.id
        )

      menu_ids = Brando.repo().all(q)

      for menu_id <- menu_ids do
        item_q =
          from(t in "navigation_items",
            select: %{
              id: t.id,
              status: t.status,
              title: t.title,
              key: t.key,
              url: t.url,
              open_in_new_window: t.open_in_new_window,
              sequence: t.sequence,
              menu_id: t.menu_id
            },
            order_by: [asc: t.sequence],
            where: t.menu_id == ^menu_id
          )

        items = Brando.repo().all(item_q)

        items =
          Enum.map(items, fn item ->
            item
            |> Map.drop([:menu_id, :sequence])
            |> Map.put(:id, Ecto.UUID.generate())
          end)

        query =
          from(t in "navigation_menus", where: t.id == ^menu_id, update: [set: [items: ^items]])

        Brando.repo().update_all(query, [])
      end
    end)

    flush()

    drop table(:navigation_items)
  end
end
