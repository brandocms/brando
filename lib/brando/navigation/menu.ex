defmodule Brando.Navigation.Menu do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Navigation",
    schema: "Menu",
    singular: "menu",
    plural: "menus",
    gettext_module: Brando.Gettext

  import Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable
  trait Brando.Trait.Status

  identifier "{{ entry.title }} [{{ entry.language }}]"

  attributes do
    attribute :title, :string, required: true
    attribute :key, :string, required: true, unique: [prevent_collision: :language]
    attribute :template, :text
  end

  relations do
    relation :items, :embeds_many, module: Brando.Navigation.Item, on_replace: :delete
  end

  forms do
    form do
      tab "Content" do
        fieldset size: :half do
          input :language, :select, options: :languages, narrow: true
          input :title, :text
          input :key, :text, monospace: true
        end

        fieldset size: :full do
          inputs_for :items,
            style: :inline,
            cardinality: :many,
            size: :full,
            default: %Brando.Navigation.Item{} do
            input :status, :select,
              options: [
                %{label: gettext("Draft"), value: :draft},
                %{label: gettext("Published"), value: :published},
                %{label: gettext("Disabled"), value: :disabled},
                %{label: gettext("Pending"), value: :pending}
              ]

            input :title, :text
            input :key, :text, monospace: true
            input :url, :text, monospace: true
            input :open_in_new_window, :toggle
          end
        end
      end
    end
  end

  listings do
    listing do
      listing_query %{
        status: :published,
        order: [{:asc, :language}, {:asc, :key}]
      }

      filters([
        [label: gettext("Title"), filter: "title"]
      ])

      actions([
        [label: gettext("Edit menu"), event: "edit_entry"],
        [
          label: gettext("Delete menu"),
          event: "delete_entry",
          confirm: gettext("Are you sure?")
        ],
        [label: gettext("Duplicate menu"), event: "duplicate_entry"],
        [label: gettext("Create menu item"), event: "create_menu_item"]
      ])

      selection_actions([
        [label: gettext("Delete menus"), event: "delete_selected"]
      ])

      field(:language, :language, columns: 1)

      template(
        """
        <a
          data-phx-link="redirect"
          data-phx-link-state="push"
          href="/admin/config/navigation/menus/update/{{ entry.id }}"
          class="entry-link">
          {{ entry.title }}
        </a>
        <br>
        <small class="monospace">{{ entry.items | size }} #{gettext("menu items")}</small><br>
        <div class="badge">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M10.758 11.828l7.849-7.849 1.414 1.414-1.414 1.415 2.474 2.474-1.414 1.415-2.475-2.475-1.414 1.414 2.121 2.121-1.414 1.415-2.121-2.122-2.192 2.192a5.002 5.002 0 0 1-7.708 6.294 5 5 0 0 1 6.294-7.708zm-.637 6.293A3 3 0 1 0 5.88 13.88a3 3 0 0 0 4.242 4.242z"/></svg>
          {{ entry.key }}
        </div>
        """,
        columns: 9
      )
    end
  end
end
