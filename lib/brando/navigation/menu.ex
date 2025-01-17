defmodule Brando.Navigation.Menu do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Navigation",
    schema: "Menu",
    singular: "menu",
    plural: "menus",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias Brando.Content.Var
  alias Brando.Navigation.Item

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable, alternates: false
  trait Brando.Trait.Status

  identifier false
  persist_identifier false

  attributes do
    attribute :title, :string, required: true
    attribute :key, :string, required: true, unique: [prevent_collision: :language]
    attribute :template, :text
  end

  relations do
    relation :items, :has_many,
      module: Brando.Navigation.Item,
      cast: true,
      drop_param: :drop_items_ids,
      sort_param: :sort_items_ids,
      on_replace: :delete,
      preload_order: [asc: :sequence]
  end

  translations do
    context :naming do
      translate :singular, t("menu")
      translate :plural, t("menus")
    end
  end

  forms do
    form do
      query &__MODULE__.form_query/1

      tab t("Content") do
        fieldset do
          size :half
          input :status, :status
          input :language, :select, options: :languages, narrow: true, label: t("Language")
          input :title, :text, label: t("Title")
          input :key, :text, monospace: true, label: t("Key")
        end

        fieldset do
          inputs_for :items do
            label t("Items")
            style :inline
            cardinality :many
            default &__MODULE__.default_item/2
            size :full

            input :language, :hidden
            input :status, :status, compact: true
            input :key, :text, monospace: true, compact: true, label: t("Key", Item)

            input :link, {:live_component, BrandoAdmin.Components.Form.Input.Link},
              compact: true,
              label: t("Link", Item)
          end
        end
      end
    end
  end

  def form_query(id) do
    %{matches: %{id: id}, preload: preloads_for()}
  end

  def default_item(_menu, _) do
    %Item{
      status: :published,
      key: "key",
      link: %Var{
        type: :link,
        key: "link",
        label: "Link",
        link_type: :url,
        link_text: "Text",
        value: "https://example.com"
      }
    }
  end

  listings do
    listing do
      query %{
        order: [{:asc, :sequence}, {:desc, :inserted_at}],
        preload: &__MODULE__.preloads_for/0
      }

      filter label: t("Title"), filter: "title"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={10}>
      {@entry.title}
      <:outside>
        <br />
        <small class="monospace">{Enum.count(@entry.items)} {gettext("menu items")}</small>
      </:outside>
    </.update_link>
    """
  end

  def preloads_for do
    children_preload =
      from i in Brando.Navigation.Item, order_by: i.sequence, preload: [link: :identifier]

    items_preload =
      from i in Brando.Navigation.Item,
        order_by: i.sequence,
        preload: [link: :identifier, children: ^children_preload]

    [
      items: items_preload
    ]
  end
end
