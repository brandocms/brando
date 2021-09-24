defmodule Brando.Sites.Redirect do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Redirect",
    singular: "redirect",
    plural: "redirects",
    gettext_module: Brando.Gettext

  import Brando.Gettext

  data_layer :embedded
  identifier "{{ entry.from }} -> {{ entry.to }}"

  attributes do
    attribute :to, :string, required: true
    attribute :from, :string, required: true
    attribute :code, :integer, required: true
  end

  translations do
    context :naming do
      translate :singular, t("redirect")
      translate :plural, t("redirects")
    end

    context :fields do
      translate :to do
        label t("To")
        placeholder t("/uri")
      end

      translate :from do
        label t("from")
        placeholder t("/uri")
      end

      translate :code do
        label t("Status Code")
        placeholder t("302")
      end
    end
  end
end
