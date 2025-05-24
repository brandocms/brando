defmodule E2eProject.Projects.Project do
  @moduledoc """
  Blueprint for Project
  """

  use Brando.Blueprint,
    application: "E2eProject",
    domain: "Projects",
    schema: "Project",
    singular: "project",
    plural: "projects"

  import Ecto.Query
  alias E2eProject.Projects

  trait Brando.Trait.Creator
  trait Brando.Trait.Meta
  trait Brando.Trait.Revisioned
  trait Brando.Trait.ScheduledPublishing
  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete, obfuscated_fields: [:slug]
  trait Brando.Trait.Status
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Translatable
  trait Brando.Trait.Blocks

  identifier "{{ entry.title }}"
  absolute_url "{% route_i18n entry.language project_path detail { entry.slug } %}"
  table "projects_projects"

  attributes do
    attribute :title, :text, required: true
    attribute :slug, :slug, unique: [prevent_collision: true], required: true
    attribute :full_case, :boolean, default: false
    attribute :introduction, :text, required: true
  end

  relations do
    relation :project_categories, :has_many,
      module: Projects.ProjectCategory,
      preload_order: [{:asc, :sequence}],
      drop_param: :drop_category_ids,
      sort_param: :sort_category_ids,
      on_replace: :delete_if_exists,
      cast: true

    relation :client, :belongs_to, module: Projects.Client, required: true
    relation :related_entries, :entries, constraints: [max_length: 3]
    relation :blocks, :has_many, module: :blocks
  end

  assets do
    asset :listing_image, :image,
      cfg: %{
        upload_path: Path.join(["images", "projects", "listing_images"]),
        sizes: %{
          "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
          "thumb" => %{"size" => "300x300>", "quality" => 70, "crop" => true},
          "small" => %{"size" => "700", "quality" => 70},
          "medium" => %{"size" => "1100", "quality" => 70},
          "large" => %{"size" => "1700", "quality" => 70},
          "xlarge" => %{"size" => "2100", "quality" => 70}
        },
        srcset: %{
          default: [
            {"small", "700w"},
            {"medium", "1100w"},
            {"large", "1700w"},
            {"xlarge", "2100w"}
          ]
        }
      }

    asset :project_gallery, :gallery,
      cfg: %{
        upload_path: Path.join(["images", "projects", "project_gallery"]),
        sizes: %{
          "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
          "thumb" => %{"size" => "300x300>", "quality" => 70, "crop" => true},
          "small" => %{"size" => "700", "quality" => 70, "crop" => true, "ratio" => "3/2"},
          "medium" => %{"size" => "1100", "quality" => 70, "crop" => true, "ratio" => "3/2"},
          "large" => %{"size" => "1700", "quality" => 70, "crop" => true, "ratio" => "3/2"},
          "xlarge" => %{"size" => "2100", "quality" => 70, "crop" => true, "ratio" => "3/2"}
        },
        srcset: %{
          default: [
            {"small", "700w"},
            {"medium", "1100w"},
            {"large", "1700w"},
            {"xlarge", "2100w"}
          ]
        }
      }
  end

  translations do
    context :naming do
      translate :singular, t("case")
      translate :plural, t("cases")
    end
  end

  forms do
    form do
      default_params %{"status" => "draft"}
      blocks :blocks, label: "Blocks"

      tab gettext("Content") do
        fieldset do
          size :full
          input :status, :status
        end

        fieldset do
          size :half
          input :title, :text, label: t("Title")
          input :slug, :slug, source: :title, show_url: true, label: t("Slug")
          input :full_case, :toggle, label: t("Full case")

          input :introduction, :rich_text,
            label: t("Introduction"),
            instructions:
              t("Used for case listings and also the heading for the case detail page"),
            extensions: ["p", "bold", "link", "color"]

          input :project_categories, :multi_select,
            options: &__MODULE__.get_categories/2,
            relation_key: :category_id,
            relation: :category,
            resetable: true,
            wrapped_labels: true,
            label: t("Categories")

          input :client_id, :select,
            options: &__MODULE__.get_clients/2,
            update_relation: {:client, &__MODULE__.get_client/1},
            resetable: true,
            label: t("Client")
        end

        fieldset do
          size :half
          shaded true
          align :end

          input :listing_image, :image,
            label: t("Listing image"),
            instructions: t("Image for the project's listing page")

          input :project_gallery, :gallery,
            label: t("Project gallery"),
            instructions: t("Images are cropped to 3/2")

          input :related_entries, :entries,
            sources: [
              {__MODULE__, %{preload: [], order: "asc title", status: :published}}
            ],
            label: t("Related entries"),
            instructions: t("Max 3")
        end
      end
    end
  end

  listings do
    listing do
      query %{
        order: [{:asc, :sequence}, {:desc, :inserted_at}]
      }

      filter(
        label: gettext("Title"),
        filter: "title"
      )

      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.field columns={2}>
      <%= if @entry.full_case do %>
        <div class="badge tiny">Case</div>
      <% end %>
    </.field>
    <.update_link entry={@entry} columns={6}>
      <%= @entry.title %>
    </.update_link>
    <.url entry={@entry} />
    """
  end

  def get_categories(_, _) do
    Projects.list_categories!(%{status: :published, order: "asc title"})
  end

  def get_clients(_, _) do
    Projects.list_clients!(%{status: :published, order: "asc name"})
  end

  def get_client(client_id) do
    Projects.get_client!(client_id)
  end

  datasources do
    datasource :all do
      type :list

      list fn _, _, _ ->
        Projects.list_projects(%{
          status: :published,
          order: [{:asc, :sequence}, {:desc, :inserted_at}],
          preload: [:categories, project_gallery: [gallery_objects: :image]]
        })
      end
    end

    datasource :featured do
      type :selection

      list fn module, _language, _vars ->
        Brando.Content.list_identifiers(module, %{status: :published})
      end

      get fn identifiers ->
        entry_ids = Enum.map(identifiers, & &1.entry_id)

        results =
          from t in __MODULE__,
            where: t.id in ^entry_ids,
            order_by: fragment("array_position(?, ?)", ^entry_ids, t.id)

        {:ok, E2eProject.Repo.all(results)}
      end
    end
  end
end
