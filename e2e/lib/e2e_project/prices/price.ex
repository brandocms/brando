defmodule E2eProject.Prices.Price do
  @moduledoc """
  Embedded Blueprint for Price
  """

  use Brando.Blueprint,
    application: "E2eProject",
    domain: "Prices",
    schema: "Price",
    singular: "price",
    plural: "prices"

  use Gettext, backend: E2eProjectAdmin.Gettext

  identifier "{{ entry.title }}"
  persist_identifier false
  data_layer :embedded

  attributes do
    attribute :title, :string, required: true
    attribute :price, :string, required: true
  end

  translations do
    context :naming do
      translate :singular, t("price")
      translate :plural, t("prices")
    end
  end
end
