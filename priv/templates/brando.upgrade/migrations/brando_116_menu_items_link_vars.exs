defmodule Brando.Repo.Migrations.MenuItemsLinkVars do
  use Ecto.Migration
  import Ecto.Query

  def up do
    create table(:navigation_items) do
      add :status, :integer
      add :sequence, :integer
      add :key, :string, null: false
      add :menu_id, references(:navigation_menus, on_delete: :delete_all)
      add :creator_id, references(:users, on_delete: :nilify_all)
      add :parent_id, references(:navigation_items, on_delete: :delete_all)
      timestamps()
    end

    alter table(:content_vars) do
      add :menu_item_id, references(:navigation_items, on_delete: :delete_all)
    end

    flush()

    # get current menus
    menus_query =
      from(m in "navigation_menus",
        select: %{
          id: m.id,
          status: m.status,
          title: m.title,
          key: m.key,
          language: m.language,
          template: m.template,
          creator_id: m.creator_id,
          sequence: m.sequence,
          inserted_at: m.inserted_at,
          updated_at: m.updated_at,
          items: m.items
        }
      )

    menus = Brando.repo().all(menus_query)

    # insert new items
    for menu <- menus do
      for item <- menu.items || [] do
        # create new menu item
        status_atom = String.to_atom(item["status"])
        {:ok, status} = Brando.Type.Status.dump(status_atom)
        menu_item = %{
          status: status,
          sequence: item["sequence"],
          key: item["key"],
          creator_id: menu.creator_id,
          inserted_at: menu.inserted_at,
          updated_at: menu.updated_at,
          menu_id: menu.id
        }

        # get the menu_item id and create a content var
        {_, [%{id: menu_item_id}]} =
          Brando.repo().insert_all("navigation_items", [menu_item], returning: [:id])

        var = %{
          type: "link",
          important: true,
          label: "Link",
          key: menu_item.key,
          width: "third",
          menu_item_id: menu_item_id,
          value: item["url"],
          link_text: item["title"],
          link_type: "url",
          link_identifier_schemas: [],
          link_target_blank: item["open_in_new_window"],
          link_allow_custom_text: true,
          creator_id: menu.creator_id,
          inserted_at: menu.inserted_at,
          updated_at: menu.updated_at
        }

        Brando.repo().insert_all("content_vars", [var])
      end
    end

    alter table(:navigation_menus) do
      remove :items
    end
  end

  def down do
    alter table(:navigation_menus) do
      add :items, :jsonb
    end

    alter table(:content_vars) do
      remove :menu_item_id
    end

    drop table(:navigation_items)
  end
end
