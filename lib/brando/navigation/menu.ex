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
        <div class="badge">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M10.758 11.828l7.849-7.849 1.414 1.414-1.414 1.415 2.474 2.474-1.414 1.415-2.475-2.475-1.414 1.414 2.121 2.121-1.414 1.415-2.121-2.122-2.192 2.192a5.002 5.002 0 0 1-7.708 6.294 5 5 0 0 1 6.294-7.708zm-.637 6.293A3 3 0 1 0 5.88 13.88a3 3 0 0 0 4.242 4.242z"/></svg>
          {{ entry.key }}
        </div>
        """,
        columns: 8
      )

      field([:items], :children_button, columns: 1)

      child_listing([
        {Brando.Navigation.Item, :items}
      ])
    end

    listing :items do
      template """
               <div class="center">⤷</div>
               """,
               columns: 1

      field :language, :language, columns: 1

      template(
        """
        <a
          data-phx-link="redirect"
          data-phx-link-state="push"
          href="/admin/config/navigation/items/update/{{ entry.id }}"
          class="entry-link">
          {{ entry.title }}
        </a>
        <br>
        <svg class="inline" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M10.758 11.828l7.849-7.849 1.414 1.414-1.414 1.415 2.474 2.474-1.414 1.415-2.475-2.475-1.414 1.414 2.121 2.121-1.414 1.415-2.121-2.122-2.192 2.192a5.002 5.002 0 0 1-7.708 6.294 5 5 0 0 1 6.294-7.708zm-.637 6.293A3 3 0 1 0 5.88 13.88a3 3 0 0 0 4.242 4.242z"/></svg>
        <small class="monospace">{{ entry.key }}</small><br>
        <svg class="inline" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M6.235 6.453a8 8 0 0 0 8.817 12.944c.115-.75-.137-1.47-.24-1.722-.23-.56-.988-1.517-2.253-2.844-.338-.355-.316-.628-.195-1.437l.013-.091c.082-.554.22-.882 2.085-1.178.948-.15 1.197.228 1.542.753l.116.172c.328.48.571.59.938.756.165.075.37.17.645.325.652.373.652.794.652 1.716v.105c0 .391-.038.735-.098 1.034a8.002 8.002 0 0 0-3.105-12.341c-.553.373-1.312.902-1.577 1.265-.135.185-.327 1.132-.95 1.21-.162.02-.381.006-.613-.009-.622-.04-1.472-.095-1.744.644-.173.468-.203 1.74.356 2.4.09.105.107.3.046.519-.08.287-.241.462-.292.498-.096-.056-.288-.279-.419-.43-.313-.365-.705-.82-1.211-.96-.184-.051-.386-.093-.583-.135-.549-.115-1.17-.246-1.315-.554-.106-.226-.105-.537-.105-.865 0-.417 0-.888-.204-1.345a1.276 1.276 0 0 0-.306-.43zM12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/></svg>
        <small class="monospace">{{ entry.url }}</small>
        """,
        columns: 13
      )

      actions([
        [label: gettext("Edit item"), event: "edit_entry"],
        [
          label: gettext("Delete item"),
          event: "delete_entry",
          confirm: gettext("Are you sure?")
        ]
      ])
    end
  end
end
