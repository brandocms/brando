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

  trait :timestamped
  trait :translatable, alternates: false

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
    relation :redirects,
             :embeds_many,
             module: Brando.Sites.Redirect,
             sort_param: :sort_redirects_ids,
             drop_param: :drop_redirects_ids,
             on_replace: :delete
  end

  forms do
    form do
      redirect_on_save &__MODULE__.redirect/3

      tab t("Content") do
        fieldset do
          label t("Default metadata")

          input :fallback_meta_title, :text,
            label: t("Fallback META title"),
            placeholder: t("Fallback META title")

          input :fallback_meta_description, :textarea,
            label: t("Fallback META description"),
            placeholder: t("Fallback META description")

          input :fallback_meta_image, :image,
            label: t("Fallback META image"),
            placeholder: t("Fallback META image")
        end

        fieldset do
          label t("Search preview")
          component &__MODULE__.search_preview/1
        end

        fieldset do
          label t("Indexing")
          input :base_url, :text, label: t("Base URL"), placeholder: t("https://yoursite.com")
          input :robots, :textarea, monospace: true, label: t("Robots"), placeholder: t("Robots")
        end

        fieldset do
          size :full

          inputs_for :redirects do
            label t("Redirects")
            style :inline
            cardinality :many
            instructions t("Use `$` at the end of test to prevent matching beyond string.")
            default %{from: "/example/:slug", to: "/new/:slug", code: 301}

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

  def search_preview(assigns) do
    image = Ecto.Changeset.get_field(assigns.form.source, :fallback_meta_image)

    assigns =
      assigns
      |> Phoenix.Component.assign(:preview_form, assigns.form)
      |> Phoenix.Component.assign(:preview_image, if(match?(%Brando.Images.Image{}, image), do: image))

    ~H"""
    <div class="seo-search-preview">
      <span class="seo-preview-url">{@preview_form[:base_url].value}</span>
      <div class="seo-preview-title">{@preview_form[:fallback_meta_title].value}</div>
      <p>{@preview_form[:fallback_meta_description].value}</p>
      <small>{gettext("Preview of the default metadata. Individual pages can override these values.")}</small>
    </div>
    <figure :if={@preview_image} class="seo-sharing-preview">
      <figcaption>{gettext("Sharing image")}</figcaption>
      <BrandoAdmin.Components.Content.image image={@preview_image} size={:xlarge} />
    </figure>
    """
  end

  def redirect(socket, _entry, _) do
    Brando.routes().admin_live_path(socket, BrandoAdmin.Sites.SEOLive)
  end
end
