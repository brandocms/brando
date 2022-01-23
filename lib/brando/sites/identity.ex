defmodule Brando.Sites.Identity do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Identity",
    singular: "identity",
    plural: "identities",
    gettext_module: Brando.Gettext

  import Brando.Gettext

  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable

  identifier "{{ entry.name }}"

  @logo_cfg [
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "xlarge",
    upload_path: Path.join(["images", "sites", "identity", "logo"]),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "400x400>", "quality" => 65, "crop" => true},
      "xlarge" => %{"size" => "1920", "quality" => 65}
    }
  ]

  attributes do
    attribute :type, :string, required: true
    attribute :name, :string, required: true
    attribute :alternate_name, :string
    attribute :email, :string, constraints: [format: ~r/@/]
    attribute :phone, :string
    attribute :address, :string
    attribute :address2, :string
    attribute :address3, :string
    attribute :zipcode, :string
    attribute :city, :string
    attribute :country, :string
    attribute :title_prefix, :string
    attribute :title, :string
    attribute :title_postfix, :string
    attribute :languages, :map, virtual: true
  end

  assets do
    asset :logo, :image, cfg: @logo_cfg
  end

  relations do
    relation :metas, :embeds_many, module: Brando.Meta, on_replace: :delete
    relation :links, :embeds_many, module: Brando.Link, on_replace: :delete
    relation :configs, :embeds_many, module: Brando.ConfigEntry, on_replace: :delete
  end

  forms do
    form do
      form_query &__MODULE__.query_with_preloads/1
      redirect_on_save &__MODULE__.redirect/3

      tab "Content" do
        fieldset do
          input :type, :radios,
            options: [
              %{value: :organization, label: t("Organization")},
              %{value: :corporation, label: t("Corporation")}
            ],
            label: t("Type")
        end

        fieldset style: :inline do
          input :name, :text, label: t("Name")

          input :alternate_name, :text,
            label: t("Alternate name"),
            instructions: t("A shortform version of the name")
        end

        fieldset style: :inline do
          input :email, :email, label: t("Email")
          input :phone, :phone, label: t("Phone")
        end

        fieldset do
          input :address, :text, label: t("Address line 1")
          input :address2, :text, label: t("Address line 2")
          input :address3, :text, label: t("Address line 3")
        end

        fieldset style: :inline do
          input :zipcode, :text, label: t("Zip code")
          input :city, :text, label: t("City")
          input :country, :text, label: t("Country")
        end

        fieldset style: :inline do
          input :title_prefix, :text, label: t("Title (prefix)")
          input :title, :text, label: t("Title")
          input :title_postfix, :text, label: t("Title (postfix)")
        end

        fieldset do
          input :logo, :image, label: t("Logo")
        end

        fieldset size: :full do
          inputs_for :links,
            label: t("Links"),
            style: :inline,
            cardinality: :many,
            size: :full,
            default: %Brando.Link{} do
            input :name, :text, label: t("Name")
            input :url, :text, label: t("URL")
          end
        end

        fieldset size: :full do
          inputs_for :metas,
            label: t("Meta properties"),
            style: :inline,
            cardinality: :many,
            size: :full,
            default: %Brando.Meta{} do
            input :key, :text, label: t("Key")
            input :value, :text, label: t("Value")
          end
        end
      end
    end
  end

  translations do
    context :naming do
      translate :singular, t("identity")
      translate :plural, t("identity")
    end
  end

  def redirect(socket, _entry, _) do
    Brando.routes().admin_live_path(socket, BrandoAdmin.Sites.IdentityLive)
  end

  def query_with_preloads(id) do
    %{matches: %{id: id}, preload: [:logo]}
  end
end
