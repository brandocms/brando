defmodule Brando.Sites.Identity do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Identity",
    singular: "identity",
    plural: "identities"

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

      # input :name, :text, class: "half"
      # input :alternate_name, :text, class: "half"
      # input :email, :email, class: "half"
      # input :phone, :phone, class: "half"

      # input :address, :text
      # input :address2, :text
      # input :address3, :text

      # input :zipcode, :text, class: "third"
      # input :city, :text, class: "third"
      # input :country, :text, class: "third"

      # input :title_prefix, :text, class: "third"
      # input :title, :text, class: "third"
      # input :title_postfix, :text, class: "third"
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
