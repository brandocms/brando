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
  trait Brando.Trait.Translatable, alternates: false
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

  translations do
    context :naming do
      translate :singular, t("menu")
      translate :plural, t("menus")
    end
  end

  forms do
    form do
      tab "Content" do
        fieldset size: :half do
          input :status, :status
          input :language, :select, options: :languages, narrow: true, label: t("Language")
          input :title, :text, label: t("Title")
          input :key, :text, monospace: true, label: t("Key")
        end

        fieldset size: :full do
          inputs_for :items,
            label: t("Items"),
            style: :inline,
            cardinality: :many,
            size: :full,
            default: %Brando.Navigation.Item{} do
            input :status, :status, compact: true, label: :hidden

            input :title, :text, label: t("Title", Brando.Navigation.Item)
            input :key, :text, monospace: true, label: t("Key", Brando.Navigation.Item)
            input :url, :text, monospace: true, label: t("URL", Brando.Navigation.Item)
            input :open_in_new_window, :toggle, label: t("New window?", Brando.Navigation.Item)
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
        [label: t("Title"), filter: "title"]
      ])

      actions([
        [label: t("Create menu item"), event: "create_menu_item"]
      ])

      field(:language, :language, columns: 1)

      template(
        """
        <div class="badge no-border no-case">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M10.758 11.828l7.849-7.849 1.414 1.414-1.414 1.415 2.474 2.474-1.414 1.415-2.475-2.475-1.414 1.414 2.121 2.121-1.414 1.415-2.121-2.122-2.192 2.192a5.002 5.002 0 0 1-7.708 6.294 5 5 0 0 1 6.294-7.708zm-.637 6.293A3 3 0 1 0 5.88 13.88a3 3 0 0 0 4.242 4.242z"/></svg>
          {{ entry.key }}
        </div>
        """,
        columns: 2
      )

      template(
        """
        <a
          data-phx-link="redirect"
          data-phx-link-state="push"
          href="/admin/config/navigation/menus/update/{{ entry.id }}"
          class="entry-link">
          {{ entry.title }}
        </a>
        """,
        columns: 4
      )

      template(
        """
        <small class="monospace">{{ entry.items | size }} #{t("menu items")}</small><br>
        """,
        columns: 3
      )
    end
  end
end
