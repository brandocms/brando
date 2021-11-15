defmodule Brando.Sites.SEO do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "SEO",
    singular: "seo",
    plural: "seos",
    gettext_module: Brando.Gettext

  @image_cfg [
    formats: [:jpg],
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
  trait Brando.Trait.Translatable

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
          input :fallback_meta_title, :text,
            label: t("Fallback META title"),
            placeholder: t("Fallback META title")

          input :fallback_meta_description, :textarea,
            label: t("Fallback META description"),
            placeholder: t("Fallback META description")

          input :fallback_meta_image, :image,
            label: t("Fallback META image"),
            placeholder: t("Fallback META image")

          input :base_url, :text, label: t("Base URL"), placeholder: t("https://yoursite.com")
          input :robots, :code, label: t("Robots"), placeholder: t("Robots")
        end

        fieldset size: :full do
          inputs_for :redirects,
            label: t("Redirects"),
            style: :inline,
            cardinality: :many,
            size: :full,
            default: %Brando.Sites.Redirect{from: "/example/:slug", to: "/new/:slug", code: 302} do
            input :code, :number, label: t("Code")
            input :from, :text, label: t("From")
            input :to, :text, label: t("To")
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
  end

  def redirect(socket, _entry) do
    Brando.routes().admin_live_path(socket, BrandoAdmin.Sites.SEOLive)
  end
end
