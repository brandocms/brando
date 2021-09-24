defmodule Brando.Sites.SEO do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "SEO",
    singular: "seo",
    plural: "seo",
    gettext_module: Brando.Gettext

  @image_cfg [
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "xlarge",
    upload_path: Path.join(["images", "sites", "identity", "image"]),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "150x150>", "quality" => 65, "crop" => true},
      "xlarge" => %{"size" => "2100", "quality" => 65}
    }
  ]

  import Brando.Gettext

  trait Brando.Trait.Timestamped

  identifier "SEO"

  attributes do
    attribute :fallback_meta_description, :text
    attribute :fallback_meta_title, :text
    attribute :base_url, :string
    attribute :robots, :text
  end

  assets do
    asset :fallback_meta_image, :image, cfg: @image_cfg
  end

  relations do
    relation :redirects, :embeds_many, module: Brando.Sites.Redirect, on_replace: :delete
  end

  forms do
    form do
      redirect_on_save &__MODULE__.redirect/2

      tab "Content" do
        fieldset do
          input :fallback_meta_title, :text
          input :fallback_meta_description, :textarea
          input :fallback_meta_image, :image

          input :base_url, :text
          input :robots, :code
        end

        fieldset size: :full do
          inputs_for :redirects,
            style: :inline,
            cardinality: :many,
            size: :full,
            default: %Brando.Sites.Redirect{from: "/example/:slug", to: "/new/:slug", code: 302} do
            input :code, :number
            input :from, :text
            input :to, :text
          end
        end
      end
    end
  end

  translations do
    context :naming do
      translate :singular, t("SEO")
      translate :plural, t("SEO")
    end

    context :fields do
      translate :fallback_meta_description do
        label t("Fallback META description")
        placeholder t("Fallback META description")
      end

      translate :fallback_meta_title do
        label t("Fallback META title")
        placeholder t("Fallback META title")
      end

      translate :fallback_meta_image do
        label t("Fallback META image")
        placeholder t("Fallback META image")
      end

      translate :base_url do
        label t("Base URL")
        placeholder t("https://yoursite.com")
      end

      translate :robots do
        label t("Robots")
        placeholder t("Robots")
      end
    end
  end

  def redirect(socket, _entry) do
    Brando.routes().admin_live_path(socket, BrandoAdmin.Sites.SEOLive)
  end
end
