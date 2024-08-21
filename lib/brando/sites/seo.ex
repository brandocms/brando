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
      "thumb" => %{"size" => "400x400>", "quality" => 65, "crop" => true},
      "xlarge" => %{"size" => "2100", "quality" => 65}
    }
  ]

  use Gettext, backend: Brando.Gettext

  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable, alternates: false

  identifier false
  persist_identifier false

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
      redirect_on_save &__MODULE__.redirect/3

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
          input :robots, :textarea, monospace: true, label: t("Robots"), placeholder: t("Robots")
        end

        fieldset size: :full do
          inputs_for :redirects,
            label: t("Redirects"),
            style: :inline,
            cardinality: :many,
            size: :full,
            instructions: t("Use `$` at the end of test to prevent matching beyond string."),
            default: %Brando.Sites.Redirect{from: "/example/:slug", to: "/new/:slug", code: 301} do
            input :code, :number, label: t("Code", Brando.Sites.Redirect)
            input :from, :text, label: t("From", Brando.Sites.Redirect)
            input :to, :text, label: t("To", Brando.Sites.Redirect)
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

  def redirect(socket, _entry, _) do
    Brando.routes().admin_live_path(socket, BrandoAdmin.Sites.SEOLive)
  end
end
