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

  table "sites_identity"
  identifier "{{ entry.name }}"

  @logo_cfg [
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "xlarge",
    upload_path: Path.join(["images", "sites", "identity", "logo"]),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "150x150>", "quality" => 65, "crop" => true},
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
    attribute :logo, :image, @logo_cfg
    attribute :languages, :map, virtual: true
  end

  relations do
    relation :metas, :embeds_many, module: Brando.Meta, on_replace: :delete
    relation :links, :embeds_many, module: Brando.Link, on_replace: :delete
    relation :configs, :embeds_many, module: Brando.ConfigEntry, on_replace: :delete
  end

  form do
    fieldset do
      input :type, :radios,
        options: [
          {:organization, gettext("Organization")},
          {:corporation, gettext("Corporation")}
        ]

      input :name, :text, class: "half"
      input :alternate_name, :text, class: "half"

      input :email, :email, class: "half"
      input :phone, :phone, class: "half"

      input :address, :text
      input :address2, :text
      input :address3, :text

      input :zipcode, :text, class: "third"
      input :city, :text, class: "third"
      input :country, :text, class: "third"

      input :title_prefix, :text, class: "third"
      input :title, :text, class: "third"
      input :title_postfix, :text, class: "third"

      input :logo, :image
    end
  end

  translations do
    context :naming do
      translate :singular, t("identity")
      translate :plural, t("identity")
    end

    context :fields do
      translate :type do
        label t("Type")
        placeholder t("Type")
      end

      translate :name do
        label t("Name")
        placeholder t("Name")
      end

      translate :alternate_name do
        label t("Alternate name")
        placeholder t("Alternate name")
        instructions t("A shortform version of the name")
      end

      translate :email do
        label t("Email")
        placeholder t("Email")
      end

      translate :phone do
        label t("Phone")
        placeholder t("Phone")
      end

      translate :address do
        label t("Address")
        placeholder t("Address")
      end

      translate :address2 do
        label t("Address - second line")
        placeholder t("Address - second line")
      end

      translate :address3 do
        label t("Address - third line")
        placeholder t("Address - third line")
      end

      translate :zipcode do
        label t("Zipcode")
        placeholder t("Zipcode")
      end

      translate :city do
        label t("City")
        placeholder t("City")
      end

      translate :country do
        label t("Country")
        placeholder t("Country")
      end

      translate :title_prefix do
        label t("Title (prefix)")
        placeholder t("Title (prefix)")
      end

      translate :title do
        label t("Title")
        placeholder t("Title")
      end

      translate :title_postfix do
        label t("Title (postfix)")
        placeholder t("Title (postfix)")
      end

      translate :logo do
        label t("Logo")
        placeholder t("Logo")
      end
    end
  end

  #   fieldset do
  #
  #   end

  #   fieldset do
  #     input :logo, :image, type: :small
  #   end

  #   fieldset do
  #     input :links, :table do
  #       editable? true
  #       deletable? true

  #       input :name, :text
  #       input :url, :text
  #     end
  #   end
  # end
end
