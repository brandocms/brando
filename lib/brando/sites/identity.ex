defmodule Brando.Sites.Identity do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Identity",
    singular: "identity",
    plural: "identities",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext

  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable, alternates: false

  identifier false
  persist_identifier false

  @logo_cfg [
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif", "image/svg+xml"],
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
    relation :metas, :embeds_many,
      module: Brando.Meta,
      on_replace: :delete,
      drop_param: :drop_metas_ids,
      sort_param: :sort_metas_ids

    relation :links, :embeds_many,
      module: Brando.Link,
      on_replace: :delete,
      drop_param: :drop_links_ids,
      sort_param: :sort_links_ids

    relation :configs, :embeds_one,
      module: Brando.Config,
      on_replace: :delete,
      drop_param: :drop_configs_ids,
      sort_param: :sort_configs_ids

    relation :type_config, :embeds_one,
      module: Brando.Sites.Identity.TypeConfig,
      on_replace: :delete
  end

  forms do
    form do
      query &__MODULE__.query_with_preloads/1
      redirect_on_save &__MODULE__.redirect/3

      tab t("Content") do
        fieldset do
          style :inline
          input :name, :text, label: t("Name")

          input :alternate_name, :text,
            label: t("Alternate name"),
            instructions: t("A shortform version of the name")
        end

        fieldset do
          style :inline
          input :email, :email, label: t("Email")
          input :phone, :phone, label: t("Phone")
        end

        fieldset do
          input :address, :text, label: t("Address line 1")
          input :address2, :text, label: t("Address line 2")
          input :address3, :text, label: t("Address line 3")
        end

        fieldset do
          style :inline
          input :zipcode, :text, label: t("Zip code")
          input :city, :text, label: t("City")
          input :country, :text, label: t("Country")
        end

        fieldset do
          style :inline
          input :title_prefix, :text, label: t("Title (prefix)")
          input :title, :text, label: t("Title")
          input :title_postfix, :text, label: t("Title (postfix)")
        end

        fieldset do
          input :logo, :image, label: t("Logo")
        end

        fieldset do
          size :half

          input :type, :select,
            options: [
              %{value: :architect, label: t("Architect"), instructions: t("Architecture offices, studios")},
              %{value: :art_gallery, label: t("Art Gallery"), instructions: t("Art galleries, exhibition spaces")},
              %{value: :corporation, label: t("Corporation"), instructions: t("Large company, publicly traded")},
              %{
                value: :educational_organization,
                label: t("Educational Organization"),
                instructions: t("Schools, universities, courses")
              },
              %{
                value: :employment_agency,
                label: t("Employment Agency"),
                instructions: t("Talent, illustration, modeling agencies")
              },
              %{
                value: :government_organization,
                label: t("Government Organization"),
                instructions: t("Public sector, government agencies")
              },
              %{value: :local_business, label: t("Local Business"), instructions: t("Physical location customers visit")},
              %{
                value: :medical_organization,
                label: t("Medical Organization"),
                instructions: t("Clinics, hospitals, practices")
              },
              %{value: :ngo, label: t("NGO"), instructions: t("Nonprofits, foundations, charities")},
              %{value: :organization, label: t("Organization"), instructions: t("Generic organization")},
              %{
                value: :professional_service,
                label: t("Professional Service"),
                instructions: t("Designers, architects, lawyers, consultants")
              },
              %{value: :restaurant, label: t("Restaurant"), instructions: t("Restaurant, cafe, bar")},
              %{value: :sports_organization, label: t("Sports Organization"), instructions: t("Clubs, teams, leagues")}
            ],
            narrow: true,
            label: t("Type"),
            instructions: t("Schema.org type used for structured data (JSON-LD)")
        end

        fieldset do
          inputs_for :type_config do
            label t("Type-specific settings")
            cardinality :one
            default %Brando.Sites.Identity.TypeConfig{}
            component BrandoAdmin.Components.Form.Input.IdentityTypeConfig
          end
        end

        fieldset do
          inputs_for :links do
            label t("Links")
            style :inline
            cardinality :many
            default %Brando.Link{}

            input :name, :text, label: t("Name", Brando.Link)
            input :url, :text, label: t("URL", Brando.Link)
          end
        end

        fieldset do
          inputs_for :metas do
            label t("Meta properties")
            style :inline
            cardinality :many
            default %Brando.Meta{}

            input :key, :text, label: t("Key", Brando.Meta)
            input :value, :text, label: t("Value", Brando.Meta)
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
