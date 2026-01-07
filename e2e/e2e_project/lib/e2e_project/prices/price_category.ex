defmodule E2eProject.Prices.PriceCategory do
  @moduledoc """
  Blueprint for PriceCategory
  """

  use Brando.Blueprint,
    application: "E2eProject",
    domain: "Prices",
    schema: "PriceCategory",
    singular: "price_category",
    plural: "price_categories"

  use Gettext, backend: E2eProjectAdmin.Gettext
  alias E2eProject.Prices

  trait Brando.Trait.Creator
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped

  identifier "{{ entry.title }}"

  attributes do
    attribute :title, :string, required: true
  end

  relations do
    relation :prices, :embeds_many,
      module: Prices.Price,
      on_replace: :delete,
      sort_param: :sort_price_ids,
      drop_param: :drop_price_ids
  end

  listings do
    listing do
      query %{
        order: [{:asc, :sequence}, {:desc, :inserted_at}]
      }

      filter label: t("Title"), key: "title"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={10}>
      {@entry.title}
    </.update_link>
    """
  end

  forms do
    form do
      default_params %{
        "status" => "published",
        "prices" => [%{title: "Default price", price: "kr 0,-"}]
      }

      tab t("Content") do
        fieldset do
          size :full
          input :status, :status
        end

        fieldset do
          size :full
          input :title, :text, label: t("Title")
        end

        fieldset do
          size :full

          inputs_for :prices do
            label t("Prices")
            style :inline
            cardinality :many
            size :full
            default %Prices.Price{}

            input :title, :text, label: t("Title")
            input :price, :text, label: t("Price")
          end
        end
      end
    end
  end

  translations do
    context :naming do
      translate :singular, t("price category")
      translate :plural, t("price categories")
    end
  end
end
