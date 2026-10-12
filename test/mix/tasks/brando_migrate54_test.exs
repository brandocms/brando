defmodule Mix.Tasks.Brando.Migrate54Test do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

  defmodule TestEndpoint do
    def url, do: "https://migration.example.test"
  end

  @blueprint_path "lib/legacy_app/projects/project.ex"
  @live_preview_path "lib/legacy_app_web/live_preview.ex"
  @repo_path "lib/legacy_app/repo.ex"
  @brando_config_path "config/brando.exs"
  @config_path "config/config.exs"
  @dockerfile_path "Dockerfile"
  @fonts_path "assets/front/css/fonts.css"
  @package_json_path "assets/package.json"
  @deployment_config_path "deployment.cfg"
  @fabfile_path "fabfile.py"
  @florist_config_path "florist.config.exs"

  @legacy_blueprint """
  defmodule LegacyApp.Projects.Project do
    use Brando.Blueprint,
      application: "LegacyApp",
      domain: "Projects",
      schema: "Project",
      singular: "project",
      plural: "projects"

    use Brando.Datasource

    trait Brando.Trait.Villain

    attribute :data, :villain
    attribute :hero_data, :villain
    attribute :metadata, :string

    relations do
      relation :hero_blocks, :has_many, module: :blocks
    end

    datasources do
      list :all, {__MODULE__, :list_all, [status: :published]}
      single :one, &__MODULE__.get_one/2
      selection :featured, &__MODULE__.list_featured/3, &__MODULE__.get_featured/1
    end

    listings do
      listing do
        listing_query %{order: "asc title"}
        filters [[label: "Title", filter: "title"], [label: "Status", key: "status"]]
        filter label: "Direct legacy", filter: "direct"
        filter label: "Already keyed", filter: "obsolete", key: "authoritative"
        actions [[label: "Duplicate", event: "duplicate"]], default_actions: false
        selection_actions [[label: "Publish", event: "publish_selected"]]
        export :editorial, label: "Editorial", fields: [:title], query: %{order: [:title]}
        component &__MODULE__.listing_row/1
      end
    end

    forms do
      form default_params: %{status: :draft} do
        form_query %{preload: [:creator]}

        fieldset [size: :half, shaded: true] do
          input :slug, :slug, for: :title
          input :related_entries, :entries, for: [{__MODULE__, %{}}]

          inputs_for :items, [cardinality: :many, style: :inline] do
            input :title, :text
          end
        end
      end

      form :secondary, [default_params: %{status: :published}] do
        fieldset do
          input :title, :text
        end
      end
    end

    json_ld_schema LegacyApp.JSONLD.Project do
      json_ld_field :author, {:references, :identity}
      json_ld_field :name, :string, [:title]
      json_ld_field :dateModified, :string, [:updated_at], &__MODULE__.format_date/1
      json_ld_field :image, LegacyApp.JSONLD.ImageObject, [:metadata, :image]
      json_ld_field :generated, :string, & &1.title
    end

    meta_schema do
      meta_field "title", [:title]
      meta_field ["description", "og:description"], [:metadata, :description], &String.trim/1
      meta_field "generated", & &1.title
      meta_field "og:locale", [:language], &encode_locale/1
    end

    def list(left, right), do: {left, right}
    def list_all(_module, _language, _vars), do: []
    def list_featured(_module, _language, _vars), do: []
    def get_featured(identifiers), do: identifiers
    def get_one(module, identifier), do: {module, identifier}
    def format_date(value), do: value
    def encode_locale(value), do: value

    def listing_row(assigns) do
      ~H\"""
      <.cover image={@entry.cover} />
      <.update_link entry={@entry}>{@entry.title}</.update_link>
      <.children_button entry={@entry} fields={[:children]} />
      \"""
    end

    def villains, do: Brando.Villain.list_villains()
    def villains_fun, do: &Brando.Villain.list_villains/0
  end
  """

  @legacy_live_preview """
  defmodule LegacyAppWeb.LivePreview do
    use Brando.LivePreview

    preview_target LegacyApp.Projects.Project do
      layout_module LegacyAppWeb.Layouts
      layout_template "application.html"
      view_module LegacyAppWeb.ProjectHTML
      view_template "show.html"
    end

    preview_target LegacyApp.Articles.Article do
      layout_module LegacyAppWeb.ArticleLayouts
      view_module LegacyAppWeb.ArticleHTML
      view_template fn entry -> entry.template end
    end
  end
  """

  @repo """
  defmodule LegacyApp.Repo do
    use Ecto.Repo,
      otp_app: :legacy_app,
      adapter: Ecto.Adapters.Postgres
  end
  """

  @brando_config """
  import Config

  config :brando,
    otp_app: :legacy_app
  """

  @config """
  import Config

  config :legacy_app, ecto_repos: [LegacyApp.Repo]
  """

  @dockerfile """
  FROM hexpm/elixir:1.18-erlang-27
  RUN mix phx.digest
  RUN mix phx.digest.clean --all
  """

  @fonts """
  @font-face {
    src: url('/fonts/legacy.woff2?vsn=d') format('woff2');
  }

  .hero { background-image: url('/images/hero.png?vsn=d'); }
  """

  @package_json """
  {
    "dependencies": {
      "phoenix_live_view": "~1.0.0",
      "unrelated": "1.0.0"
    }
  }
  """

  @deployment_config """
  [DEPLOYMENT]
  PROJECT_MODULE = LegacyApp
  PROJECT_NAME = legacy_app
  PROD_URL = https://example.com
  DB_PASS = legacy-secret
  DOCKER_HOST =
  SSH_USER = deploy
  SSH_PASS = legacy-ssh-secret
  SSH_HOST = example.com
  SSH_PORT = 2222
  """

  @fabfile """
  GLUE_SETTINGS = {
      'project_name': PROJECT_NAME,
      'project_group': 'web',
      'prod': {
          'project_base': '/sites/prod',
          'process_name': '%s_prod' % PROJECT_NAME,
          'db_name': '%s_prod' % PROJECT_NAME,
          'db_user': PROJECT_NAME,
      }
  }

  def prod():
      env.flavor = 'prod'
      env.mix_env = 'prod'
      env.dockerfile = 'Dockerfile'
  """

  test "rewrites the supported legacy Blueprint surface without changing unrelated calls" do
    igniter = migrate(@legacy_blueprint, @legacy_live_preview)
    blueprint = source(igniter, @blueprint_path)

    refute blueprint =~ "use Brando.Datasource"
    assert blueprint =~ "trait(Brando.Trait.Blocks)"
    refute blueprint =~ ":villain"
    assert count(blueprint, "relation(:blocks, :has_many, module: :blocks)") == 1
    assert count(blueprint, "relation(:hero_blocks, :has_many, module: :blocks)") == 1

    assert blueprint =~ "datasource(:all) do"
    assert blueprint =~ "type(:list)"
    assert blueprint =~ "list({__MODULE__, :list_all, [status: :published]})"
    assert blueprint =~ "datasource(:featured) do"
    assert blueprint =~ "type(:selection)"
    assert blueprint =~ "datasource(:one) do"
    assert blueprint =~ "type(:single)"
    assert blueprint =~ "get(fn identifier ->"
    assert blueprint =~ "__MODULE__.get_one(to_string(__MODULE__), identifier)"
    refute blueprint =~ ").("
    assert blueprint =~ "def list(left, right), do: {left, right}"
    assert blueprint =~ "Brando.Villain.list_blocks()"
    refute blueprint =~ "list_villains"

    assert blueprint =~ "query(%{order: \"asc title\"})"
    assert blueprint =~ "filter(label: \"Title\", key: \"title\")"
    assert blueprint =~ "filter(label: \"Direct legacy\", key: \"direct\")"
    assert blueprint =~ "filter(label: \"Already keyed\", key: \"authoritative\")"
    refute blueprint =~ "obsolete"
    refute blueprint =~ "filter: \""
    assert blueprint =~ "action(label: \"Duplicate\", event: \"duplicate\")"
    assert blueprint =~ "default_actions(false)"
    assert blueprint =~ "selection_action(label: \"Publish\", event: \"publish_selected\")"
    assert blueprint =~ "export(:editorial) do"
    assert blueprint =~ "label(\"Editorial\")"
    assert blueprint =~ "fields([:title])"
    assert blueprint =~ "query(%{preload: [:creator]})"
    assert blueprint =~ "input(:slug, :slug, source: :title)"
    assert blueprint =~ "input(:related_entries, :entries, sources: [{__MODULE__, %{}}])"
    assert blueprint =~ ~r/field\(\s*:author,\s*:identity\s*\)/
    assert blueprint =~ "field(:name, :string, fn entry ->"
    assert blueprint =~ "get_in(entry, [Access.key(:title)])"
    assert blueprint =~ "field(:dateModified, :string, fn entry ->"
    assert blueprint =~ "__MODULE__.format_date(get_in(entry, [Access.key(:updated_at)]))"
    assert blueprint =~ "field(:image, LegacyApp.JSONLD.ImageObject, fn entry ->"
    assert blueprint =~ "Access.key(:metadata), Access.key(:image)"
    assert blueprint =~ "field(:generated, :string, & &1.title)"
    assert blueprint =~ "field(\"title\", fn entry ->"

    assert blueprint =~
             ~r/field\(\s*\["description", "og:description"\],\s*fn entry ->/

    assert blueprint =~ "String.trim(get_in(entry, [Access.key(:metadata), Access.key(:description)]))"
    # koi's og:locale
    assert blueprint =~ ~s|field("og:locale", fn entry -> encode_locale(get_in(entry, [Access.key(:language)])) end)|
    assert blueprint =~ "field(\"generated\", & &1.title)"

    refute blueprint =~ "Listings.Components"

    assert blueprint =~ "form do\n      default_params(%{status: :draft})"
    assert blueprint =~ "form :secondary do\n      default_params(%{status: :published})"
    assert blueprint =~ "fieldset do\n        size(:half)\n        shaded(true)"
    assert blueprint =~ "inputs_for :items do\n          cardinality(:many)\n          style(:inline)"
    refute blueprint =~ "status(:draft)"
    refute blueprint =~ "status(:published)"
  end

  @villain_editor_blueprint """
  defmodule LegacyApp.Vacancies.Vacancy do
    use Brando.Blueprint,
      application: "LegacyApp",
      domain: "Vacancies",
      schema: "Vacancy",
      singular: "vacancy",
      plural: "vacancies"

    trait Brando.Trait.Villain

    attributes do
      attribute :title, :string
      attribute :data, :villain
      attribute :hero_data, :villain
    end

    forms do
      form do
        tab "Content" do
          fieldset size: :full do
            input :title, :text
          end

          fieldset size: :full do
            input :data, :blocks, label: "Innholdsblokker", template_namespace: "vacancies"
          end
        end

        tab "Hero" do
          fieldset size: :full do
            input :hero_data, :blocks
          end
        end
      end

      form :compact do
        # Only the title
        tab "Content" do
          fieldset size: :full do
            input :title, :text
            input :data, :blocks
          end
        end
      end
    end
  end
  """

  test "moves the Villain block editor inputs to form-level block editors" do
    igniter = migrate(@villain_editor_blueprint, nil)
    blueprint = source(igniter, @blueprint_path)

    refute blueprint =~ ":blocks, :blocks"
    refute blueprint =~ "input(:data"
    refute blueprint =~ "input(:hero_data"
    refute blueprint =~ ~s(tab "Hero")

    assert blueprint =~
             ~r/form do\n\s+blocks\(:blocks, label: "Innholdsblokker", template_namespace: "vacancies"\)\n\s+blocks\(:hero_blocks\)\n\n\s+tab "Content" do/

    assert blueprint =~
             ~r/form :compact do\n\s+blocks\(:blocks\)\n\s+# Only the title\n\s+tab "Content" do\n\s+fieldset do\n\s+size\(:full\)\n\s+input\(:title, :text\)\n\s+end/

    assert count(blueprint, "input(:title, :text)") == 2
    assert count(blueprint, "fieldset do") == 2

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, @blueprint_path)
  end

  test "carries only the options form-level blocks accepts, and names the others" do
    blueprint = """
    defmodule LegacyApp.Vacancies.Vacancy do
      use Brando.Blueprint,
        application: "LegacyApp",
        domain: "Vacancies",
        schema: "Vacancy",
        singular: "vacancy",
        plural: "vacancies"

      trait Brando.Trait.Villain

      attributes do
        attribute :data, :villain
      end

      forms do
        form do
          tab "Content" do
            fieldset size: :full do
              input :data, :blocks,
                label: "Innhold",
                instructions: "Skriv innholdet her",
                template_namespace: "vacancies",
                monospace: true
            end
          end
        end
      end
    end
    """

    igniter = migrate(blueprint, nil)
    migrated = source(igniter, @blueprint_path)

    assert migrated =~ ~s|blocks(:blocks, label: "Innhold", template_namespace: "vacancies")|
    refute migrated =~ "instructions"
    refute migrated =~ "monospace"

    assert_has_warning(igniter, fn warning ->
      warning =~ "#{@blueprint_path}:19: `instructions`" and warning =~ "#{@blueprint_path}:19: `monospace`"
    end)

    module = Module.concat(__MODULE__, "DroppedOptions#{System.unique_integer([:positive])}")

    compiled =
      migrated
      |> String.replace("LegacyApp.Vacancies.Vacancy", inspect(module))
      |> String.replace(~s|plural: "vacancies"|, ~s|plural: "vacancies",\n    gettext_module: Brando.Gettext|)

    warnings = ExUnit.CaptureIO.capture_io(:stderr, fn -> Code.compile_string(compiled) end)
    refute warnings =~ "DslError"
    assert [%{name: :blocks, opts: opts}] = module.__form__().blocks
    assert opts[:template_namespace] == "vacancies"
  end

  test "moves a block editor input an earlier migrate54 run left behind" do
    left_behind = """
    defmodule LegacyApp.Vacancies.Vacancy do
      use Brando.Blueprint,
        application: "LegacyApp",
        domain: "Vacancies",
        schema: "Vacancy",
        singular: "vacancy",
        plural: "vacancies"

      trait Brando.Trait.Blocks

      forms do
        form do
          tab "Content" do
            fieldset do
              size :full
              input :data, :blocks, label: "Innholdsblokker"
            end
          end
        end
      end

      relations do
        relation :blocks, :has_many, module: :blocks
      end
    end
    """

    blueprint = left_behind |> migrate(nil) |> source(@blueprint_path)

    refute blueprint =~ "input(:data"
    assert blueprint =~ ~s|blocks(:blocks, label: "Innholdsblokker")|
    refute blueprint =~ ~s(tab "Content")
  end

  test "points the moved schemas' templates at their rendered blocks and lists what it left" do
    templates = %{
      "lib/legacy_app_web/controllers/vacancy_html/detail.html.heex" => """
      <main>
        <%= @entry.html |> raw %>
        <%= raw(@vacancy.hero_html) %>
        <%= render("show.html") %>
      </main>
      """,
      "lib/legacy_app_web/controllers/vacancy_html.ex" => """
      defmodule LegacyAppWeb.VacancyHTML do
        def body(vacancy), do: Phoenix.HTML.raw(vacancy.html)
      end
      """,
      "lib/legacy_app_web/templates/vacancy/show.html.eex" => "<%= raw @entry.html %>\n",
      "lib/legacy_app_web/controllers/page_html/show.html.heex" => "<%= @page.html |> raw %>\n",
      "lib/legacy_app_web/components/featured.html.heex" => "<%= @featured.html |> raw %>\n",
      "lib/legacy_app_web/components/navigation.html.heex" => """
      <%= for item <- @navigation.items do %>
        <a href={item.url}><%= item.title %></a>
      <% end %>
      <%= for product <- @products.items do %><%= product.url %><% end %>
      """,
      "lib/legacy_app_web/controllers/page_controller.ex" => """
      defmodule LegacyAppWeb.PageController do
        def heading(page), do: Brando.Pages.get_var(page, "heading")
      end
      """
    }

    igniter = migrate(@villain_editor_blueprint, nil, templates)

    assert source(igniter, "lib/legacy_app_web/controllers/vacancy_html/detail.html.heex") == """
           <main>
             <%= @entry.rendered_blocks |> raw %>
             <%= raw(@vacancy.rendered_hero_blocks) %>
             <%= render("show.html") %>
           </main>
           """

    assert source(igniter, "lib/legacy_app_web/controllers/vacancy_html.ex") =~ "raw(vacancy.rendered_blocks)"
    assert source(igniter, "lib/legacy_app_web/templates/vacancy/show.html.eex") == "<%= raw @entry.rendered_blocks %>\n"

    assert source(igniter, "lib/legacy_app_web/controllers/page_html/show.html.heex") ==
             "<%= @page.rendered_blocks |> raw %>\n"

    assert_unchanged(igniter, [
      "lib/legacy_app_web/components/featured.html.heex",
      "lib/legacy_app_web/controllers/page_controller.ex"
    ])

    assert source(igniter, "lib/legacy_app_web/components/navigation.html.heex") =~
             "<a href={Brando.HTML.get_menu_item_url(item)}><%= Brando.HTML.get_menu_item_text(item) %></a>"

    assert_has_warning(igniter, fn warning ->
      warning =~ "Template code that 0.54 breaks" and
        warning =~ "lib/legacy_app_web/components/featured.html.heex:1: <%= @featured.html |> raw %>" and
        not (warning =~ "navigation.html.heex") and
        warning =~ "lib/legacy_app_web/controllers/page_controller.ex:2: def heading(page), do: Brando.Pages.get_var" and
        not (warning =~ "vacancy_html")
    end)

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, Map.keys(templates))
  end

  test "rewrites Villain html reads only in Elixir code, and lists the others" do
    templates = %{
      "lib/legacy_app_web/templates/vacancy/show.html.eex" => """
      <script>const entry = {html: "Hello"}; el.innerHTML = entry.html;</script>
      <%= raw @entry.html %>
      <p>Read entry.html for details</p>
      """,
      "lib/legacy_app_web/controllers/vacancy_html/show.html.heex" => """
      <div title="Ærlig">{@entry.html}</div>
      <script>window.entry = {}; console.log(entry.html)</script>
      <.card body={@entry.html} /><p>About entry.html</p>
      """,
      "lib/legacy_app_web/controllers/vacancy_html.ex" => ~S'''
      defmodule LegacyAppWeb.VacancyHTML do
        def body(vacancy), do: Phoenix.HTML.raw(vacancy.html)
        def note, do: "Ærlig: see vacancy.html, or #{vacancy().html}"
        def vacancy, do: %{html: ""}

        def show(assigns) do
          ~H"""
          <div>{@entry.html}</div>
          <script>let entry = {}; entry.html = 1</script>
          """
        end
      end
      '''
    }

    igniter = migrate(@villain_editor_blueprint, nil, templates)

    assert source(igniter, "lib/legacy_app_web/templates/vacancy/show.html.eex") == """
           <script>const entry = {html: "Hello"}; el.innerHTML = entry.html;</script>
           <%= raw @entry.rendered_blocks %>
           <p>Read entry.html for details</p>
           """

    assert source(igniter, "lib/legacy_app_web/controllers/vacancy_html/show.html.heex") == """
           <div title="Ærlig">{@entry.rendered_blocks}</div>
           <script>window.entry = {}; console.log(entry.html)</script>
           <.card body={@entry.rendered_blocks} /><p>About entry.html</p>
           """

    assert source(igniter, "lib/legacy_app_web/controllers/vacancy_html.ex") == ~S'''
           defmodule LegacyAppWeb.VacancyHTML do
             def body(vacancy), do: Phoenix.HTML.raw(vacancy.rendered_blocks)
             def note, do: "Ærlig: see vacancy.html, or #{vacancy().html}"
             def vacancy, do: %{html: ""}

             def show(assigns) do
               ~H"""
               <div>{@entry.rendered_blocks}</div>
               <script>let entry = {}; entry.html = 1</script>
               """
             end
           end
           '''

    assert_has_warning(igniter, fn warning ->
      Enum.all?(
        [
          "templates/vacancy/show.html.eex:1:",
          "templates/vacancy/show.html.eex:3:",
          "vacancy_html/show.html.heex:2:",
          "vacancy_html/show.html.heex:3:",
          "vacancy_html.ex:3:",
          "vacancy_html.ex:9:"
        ],
        &String.contains?(warning, &1)
      ) and not (warning =~ "show.html.eex:2:") and not (warning =~ "vacancy_html.ex:2:")
    end)
  end

  test "rewrites templates of a Blueprint an earlier run moved, unless another schema shares its singular" do
    moved = """
    defmodule LegacyApp.Articles.Category do
      use Brando.Blueprint,
        application: "LegacyApp",
        domain: "Articles",
        schema: "Category",
        singular: "category",
        plural: "categories"

      trait Brando.Trait.Blocks

      relations do
        relation :blocks, :has_many, module: :blocks
      end
    end
    """

    plain = """
    defmodule LegacyApp.Menu.Category do
      use Brando.Blueprint,
        application: "LegacyApp",
        domain: "Menu",
        schema: "Category",
        singular: "category",
        plural: "categories"

      attributes do
        attribute :html, :text
      end
    end
    """

    article =
      String.replace(moved, ["Articles.Category", "\"Category\"", "\"category\"", "\"categories\""], fn
        "Articles.Category" -> "Articles.Article"
        "\"Category\"" -> "\"Article\""
        "\"category\"" -> "\"article\""
        "\"categories\"" -> "\"articles\""
      end)

    igniter =
      migrate(article, nil, %{
        "lib/legacy_app/articles/category.ex" => moved,
        "lib/legacy_app/menu/category.ex" => plain,
        "lib/legacy_app_web/controllers/article_html/show.html.heex" => "<%= @entry.html |> raw %>\n",
        "lib/legacy_app_web/controllers/category_html/show.html.heex" => "<%= @entry.html |> raw %>\n"
      })

    assert source(igniter, "lib/legacy_app_web/controllers/article_html/show.html.heex") ==
             "<%= @entry.rendered_blocks |> raw %>\n"

    assert_unchanged(igniter, "lib/legacy_app_web/controllers/category_html/show.html.heex")

    assert_has_warning(
      igniter,
      &(&1 =~ "schemas that share a singular (category)" and &1 =~ "category_html/show.html.heex:1")
    )
  end

  @router_path "lib/legacy_app_web/router.ex"

  @router """
  defmodule LegacyAppWeb.Router do
    use LegacyAppWeb, :router
    import Brando.Router

    admin_routes do
      live "/", LegacyAppAdmin.DashboardLive

      scope "/banners", LegacyAppAdmin.Banners do
        live "/banners", BannerListLive
        live "/banners/create", BannerCreateLive
        live "/banners/update/:entry_id", BannerUpdateLive
      end

      scope "/menu", LegacyAppAdmin.Menu, as: :menu do
        live "/categories", CategoryListLive
        live "/categories/create", CategoryCreateLive
        live "/categories/update/:entry_id", CategoryUpdateLive
      end

      live "/articles/articles", LegacyAppAdmin.Articles.ArticleListLive
      live "/articles/articles/create", LegacyAppAdmin.Articles.ArticleCreateLive
      live "/articles/articles/update/:entry_id", LegacyAppAdmin.Articles.ArticleUpdateLive
      live "/articles/categories/create", LegacyAppAdmin.Articles.CategoryCreateLive
      live "/articles/categories/update/:entry_id", LegacyAppAdmin.Articles.CategoryUpdateLive

      live "/projects/projects/create", LegacyAppAdmin.Projects.ProjectCreateLive
      live "/projects/projects/update/:entry_id", LegacyAppAdmin.Projects.ProjectUpdateLive
    end
  end
  """

  defp admin_view(module, schema, action, opts \\ []) do
    singular = schema |> String.split(".") |> List.last() |> Macro.underscore()
    entry_id = if action == :update, do: "\n      entry_id={@entry_id}", else: ""
    presences = if action == :update, do: "\n      presences={@presences}", else: ""
    header = Keyword.get(opts, :header, "Update #{singular}")

    """
    defmodule #{module} do
      use BrandoAdmin.LiveView.Form, schema: #{Keyword.get(opts, :schema_prefix, "")}#{schema}
      alias BrandoAdmin.Components.Form
      #{Keyword.get(opts, :gettext, "import LegacyAppAdmin.Gettext, warn: false")}

      def render(assigns) do
        ~H\"\"\"
        <.live_component module={Form}
          id="#{singular}_form"#{entry_id}
          current_user={@current_user}#{presences}
          schema={@schema}>
          <:header>
            <%= gettext("#{header}") %>
          </:header>
        </.live_component>
        \"\"\"
      end
    #{Keyword.get(opts, :extra, "")}end
    """
  end

  @content_header_create """
  defmodule LegacyAppAdmin.Menu.CategoryCreateLive do
    use BrandoAdmin.LiveView.Form, schema: LegacyApp.Menu.Category
    alias BrandoAdmin.Components.Content
    alias BrandoAdmin.Components.Form

    use Gettext,
      backend: LegacyAppAdmin.Gettext

    def render(assigns) do
      ~H\"\"\"
      <Content.header
        title={gettext("Categories")}
        subtitle={gettext("Create category")} />

      <.live_component module={Form}
        id="category_form"
        current_user={@current_user}
        schema={@schema}
      />
      \"\"\"
    end
  end
  """

  defp admin_views do
    %{
      @router_path => @router,
      "lib/legacy_app_admin/live/banners/banner_create_live.ex" =>
        admin_view("LegacyAppAdmin.Banners.BannerCreateLive", "LegacyApp.Banners.Banner", :create),
      "lib/legacy_app_admin/live/banners/banner_update_live.ex" =>
        admin_view("LegacyAppAdmin.Banners.BannerUpdateLive", "LegacyApp.Banners.Banner", :update,
          schema_prefix: "Elixir."
        ),
      "lib/legacy_app_admin/live/menu/category_create_live.ex" => @content_header_create,
      "lib/legacy_app_admin/live/menu/category_update_live.ex" =>
        admin_view("LegacyAppAdmin.Menu.CategoryUpdateLive", "LegacyApp.Menu.Category", :update,
          gettext: "use Gettext, backend: LegacyAppAdmin.Gettext"
        ),
      "lib/legacy_app_admin/live/articles/article_create_live.ex" =>
        admin_view("LegacyAppAdmin.Articles.ArticleCreateLive", "LegacyApp.Articles.Article", :create),
      "lib/legacy_app_admin/live/articles/article_update_live.ex" =>
        admin_view("LegacyAppAdmin.Articles.ArticleUpdateLive", "LegacyApp.Articles.Article", :update),
      "lib/legacy_app_admin/live/articles/category_create_live.ex" =>
        admin_view("LegacyAppAdmin.Articles.CategoryCreateLive", "LegacyApp.Articles.Category", :create),
      "lib/legacy_app_admin/live/articles/category_update_live.ex" =>
        admin_view("LegacyAppAdmin.Articles.CategoryUpdateLive", "LegacyApp.Articles.Category", :update),
      "lib/legacy_app_admin/live/projects/project_create_live.ex" =>
        admin_view("LegacyAppAdmin.Projects.ProjectCreateLive", "LegacyApp.Projects.Project", :create),
      "lib/legacy_app_admin/live/projects/project_update_live.ex" =>
        admin_view("LegacyAppAdmin.Projects.ProjectUpdateLive", "LegacyApp.Projects.Project", :update,
          extra: "\n  def handle_event(\"publish\", _params, socket), do: {:noreply, socket}\n"
        )
    }
  end

  test "replaces generated admin Create/Update LiveViews with a FormLive and routes it" do
    igniter = migrate(@legacy_blueprint, nil, admin_views())

    converted = [
      {"banners/banner", "LegacyAppAdmin.Banners.BannerFormLive", "LegacyApp.Banners.Banner", "banner"},
      {"menu/category", "LegacyAppAdmin.Menu.CategoryFormLive", "LegacyApp.Menu.Category", "category"},
      {"articles/article", "LegacyAppAdmin.Articles.ArticleFormLive", "LegacyApp.Articles.Article", "article"},
      {"articles/category", "LegacyAppAdmin.Articles.CategoryFormLive", "LegacyApp.Articles.Category", "category"}
    ]

    for {path, module, schema, singular} <- converted do
      assert_creates(igniter, "lib/legacy_app_admin/live/#{path}_form_live.ex", fn contents ->
        assert contents =~ "defmodule #{module} do"
        assert contents =~ "use BrandoAdmin.LiveView.Form, schema: #{schema}\n"
        assert contents =~ "use Gettext, backend: LegacyAppAdmin.Gettext, warn: false"
        assert contents =~ ~s(id="#{singular}_form")
        assert contents =~ "entry_id={@entry_id}"
        refute contents =~ "header"
      end)

      assert "lib/legacy_app_admin/live/#{path}_create_live.ex" in igniter.rms
      assert "lib/legacy_app_admin/live/#{path}_update_live.ex" in igniter.rms
    end

    router = source(igniter, @router_path)
    assert router =~ ~s|live("/banners/create", BannerFormLive, :create)|
    assert router =~ ~s|live("/banners/update/:entry_id", BannerFormLive, :update)|
    assert router =~ ~s|live("/banners", BannerListLive)|
    assert router =~ ~s|live("/categories/create", CategoryFormLive, :create)|
    assert router =~ ~s|live("/articles/articles/create", LegacyAppAdmin.Articles.ArticleFormLive, :create)|

    assert router =~
             ~r|live\(\s*"/articles/categories/update/:entry_id",\s*LegacyAppAdmin.Articles.CategoryFormLive,\s*:update\s*\)|

    # Edited: kept, routes unchanged, listed.
    refute "lib/legacy_app_admin/live/projects/project_update_live.ex" in igniter.rms
    assert router =~ ~s|live("/projects/projects/create", LegacyAppAdmin.Projects.ProjectCreateLive)|

    assert_has_warning(igniter, fn warning ->
      warning =~ "left for you to merge into one FormLive" and
        warning =~ "LegacyAppAdmin.Projects.Project{Create,Update}Live" and
        warning =~ "differs from what the generator wrote"
    end)

    # Articles.Category is not scoped `as:`; Menu.Category is.
    assert_has_warning(igniter, fn warning ->
      warning =~ "share a route helper" and
        warning =~ "LegacyApp.Articles.Category, LegacyApp.Menu.Category: admin_category_form_path" and
        warning =~ "router_scope: :menu"
    end)

    assert_has_notice(
      igniter,
      &(&1 =~ "LegacyAppAdmin.Banners.BannerFormLive (lib/legacy_app_admin/live/banners/banner_form_live.ex)")
    )

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()

    assert_unchanged(rerun, [@router_path | Enum.map(converted, &"lib/legacy_app_admin/live/#{elem(&1, 0)}_form_live.ex")])
  end

  test "leaves a Create/Update pair not named as the generator named it" do
    router = """
    defmodule LegacyAppWeb.Router do
      use LegacyAppWeb, :router
      import Brando.Router

      admin_routes do
        live "/projects/create", LegacyAppAdmin.ProjectCreateLive
        live "/projects/update/:entry_id", LegacyAppAdmin.ProjectUpdateLive
        live "/articles/create", LegacyAppAdmin.Content.ArticleCreateLive
        live "/articles/update/:entry_id", LegacyAppAdmin.Content.ArticleUpdateLive
      end
    end
    """

    views = %{
      @router_path => router,
      "lib/legacy_app_admin/live/project_create_live.ex" =>
        admin_view("LegacyAppAdmin.ProjectCreateLive", "LegacyApp.Projects.Project", :create),
      "lib/legacy_app_admin/live/project_update_live.ex" =>
        admin_view("LegacyAppAdmin.ProjectUpdateLive", "LegacyApp.Projects.Project", :update),
      # The generator named the views after the schema's domain.
      "lib/legacy_app_admin/live/content/article_create_live.ex" =>
        admin_view("LegacyAppAdmin.Content.ArticleCreateLive", "LegacyApp.Articles.Article", :create),
      "lib/legacy_app_admin/live/content/article_update_live.ex" =>
        admin_view("LegacyAppAdmin.Content.ArticleUpdateLive", "LegacyApp.Articles.Article", :update)
    }

    igniter = migrate(@legacy_blueprint, nil, views)

    assert igniter.issues == []
    assert igniter.rms == []
    refute_creates(igniter, "lib/legacy_app_admin/live/project_form_live.ex")
    refute_creates(igniter, "lib/legacy_app_admin/live/content/article_form_live.ex")
    assert_unchanged(igniter, Map.keys(views))

    assert_has_warning(igniter, fn warning ->
      warning =~ "LegacyAppAdmin.Project{Create,Update}Live" and
        warning =~ "LegacyAppAdmin.Content.Article{Create,Update}Live" and
        warning =~ "is not named as the generator named it"
    end)
  end

  test "leaves a Create/Update pair whose routes it cannot find" do
    views =
      admin_views()
      |> Map.take([
        "lib/legacy_app_admin/live/banners/banner_create_live.ex",
        "lib/legacy_app_admin/live/banners/banner_update_live.ex"
      ])
      |> Map.put(@router_path, String.replace(@router, "BannerCreateLive", "BannerCreateLive, :create"))

    igniter = migrate(@legacy_blueprint, nil, views)

    assert igniter.rms == []
    refute_creates(igniter, "lib/legacy_app_admin/live/banners/banner_form_live.ex")
    assert_has_warning(igniter, &(&1 =~ "its routes are not `live \"path\", Module` lines in the router"))
  end

  test "lists the files it creates and changes, for --yes, which shows no diff" do
    igniter = @legacy_blueprint |> migrate(nil) |> Mix.Brando.Igniter.SourceTask.list_written_files()

    assert_has_notice(igniter, fn notice ->
      notice =~ "Files written:" and
        notice =~ "  created: scripts/sync_gettext.sh" and
        notice =~ "  updated: #{@blueprint_path}" and
        notice =~ "  updated: #{@dockerfile_path}" and
        not (notice =~ @repo_path)
    end)
  end

  test "rewrites each LivePreview target with its own modules and preserves callback behavior" do
    igniter = migrate(@legacy_blueprint, @legacy_live_preview)
    live_preview = source(igniter, @live_preview_path)

    refute live_preview =~ "layout_module"
    refute live_preview =~ "layout_template"
    refute live_preview =~ "view_module"
    refute live_preview =~ "view_template"
    assert live_preview =~ "layout({LegacyAppWeb.Layouts, \"application\"})"
    assert live_preview =~ "template({LegacyAppWeb.ProjectHTML, \"show.html\"})"
    assert live_preview =~ "layout({LegacyAppWeb.ArticleLayouts, :app})"
    assert live_preview =~ "{LegacyAppWeb.ArticleHTML,"
    assert live_preview =~ "(fn entry -> entry.template end).(entry)"
  end

  test "compiled migrations preserve datasource, Meta, and JSON-LD behavior" do
    previous = Application.fetch_env(:brando, :endpoint_module)
    Application.put_env(:brando, :endpoint_module, TestEndpoint)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:brando, :endpoint_module, value)
        :error -> Application.delete_env(:brando, :endpoint_module)
      end
    end)

    unique = System.unique_integer([:positive])
    module = Module.concat(__MODULE__, "MigratedBlueprint#{unique}")
    schema = "MigratedBlueprint#{unique}"

    legacy_blueprint = """
    defmodule #{inspect(module)} do
      use Brando.Blueprint,
        application: "Brando",
        domain: "Migrate54Test",
        schema: #{inspect(schema)},
        singular: "migrated_blueprint",
        plural: "migrated_blueprints",
        gettext_module: Brando.Gettext

      use Brando.Datasource

      trait Brando.Trait.Villain

      attribute :data, :villain

      forms do
        form do
          tab "Content" do
            fieldset size: :full do
              input :data, :blocks, label: "Content"
            end
          end
        end
      end

      datasources do
        single :one, &__MODULE__.get_one/2
      end

      listings do
        listing do
          component &__MODULE__.listing_row/1
        end
      end

      json_ld_schema Brando.JSONLD.Schema.Article do
        json_ld_field :author, {:references, :identity}
        json_ld_field :publisher, {:references, :publisher}
        json_ld_field :name, :string, [:title]
        json_ld_field :description, :string, [:metadata, :description], &String.trim/1
        json_ld_field :creator, Brando.JSONLD.Schema.Person, [:creator]

        json_ld_field :copyrightHolder, Brando.JSONLD.Schema.Person, [:creator], fn creator ->
          Map.update!(creator, :name, &String.upcase/1)
        end
      end

      meta_schema do
        meta_field ["title", "og:title"], [:title]
        meta_field "description", [:metadata, :description], &String.trim/1
      end

      def get_one(module_name, identifier), do: {:ok, {module_name, identifier}}

      def listing_row(assigns) do
        ~H\"\"\"
        <div>{@entry.title}</div>
        \"\"\"
      end
    end
    """

    migrated_source = legacy_blueprint |> migrate(nil) |> source(@blueprint_path)
    assert migrated_source =~ "relation(:blocks, :has_many, module: :blocks)"
    warnings = ExUnit.CaptureIO.capture_io(:stderr, fn -> Code.compile_string(migrated_source) end)
    refute warnings =~ "DslError"
    refute warnings =~ "unknown"
    assert [%{name: :blocks}] = module.__form__().blocks

    assert Brando.Datasource.get_single(module, :one, 42) ==
             {:ok, {to_string(module), 42}}

    data = %{
      title: "Migration title",
      metadata: %{description: "  Migration description  "},
      creator: %{name: "Ada"}
    }

    assert module |> Brando.Blueprint.Meta.extract_meta(data) |> Map.new() == %{
             "description" => "Migration description",
             "og:title" => "Migration title",
             "title" => "Migration title"
           }

    json_ld = Brando.JSONLD.extract_json_ld(module, data)

    assert json_ld.author == %{"@id": "#{Brando.Utils.hostname()}/#identity"}
    assert json_ld.publisher == %{"@id" => "#{Brando.Utils.hostname()}/#publisher"}
    assert json_ld.name == "Migration title"
    assert json_ld.description == "Migration description"
    assert json_ld.creator.name == "Ada"
    assert json_ld.copyrightHolder.name == "ADA"
  end

  test "is idempotent across Blueprint, LivePreview, and copied-file changes" do
    first_pass = migrate(@legacy_blueprint, @legacy_live_preview)

    second_pass =
      first_pass
      |> apply_igniter!()
      |> include_test_files()
      |> Migrate54.igniter()

    assert_unchanged(second_pass)
  end

  # `Path.expand/1` on these globs put absolute paths into the rewrite. Igniter then
  # takes each source's first path segment to find `.formatter.exs`, got "/" back,
  # and ran `Path.wildcard("/**/.formatter.exs")` — a walk of the whole filesystem,
  # so the task never returned.
  #
  # This is asserted against the source because Igniter's test mode relativizes
  # every included path before storing it, which hides the difference: the task
  # behaves identically here whether the globs are absolute or not.
  test "includes its globs relative to the project root" do
    source = File.read!("lib/mix/brando/igniter/source_upgrade.ex")

    refute source =~ ~r/include_glob\(\s*Path\.expand/,
           "include_glob/2 must receive a project-relative glob"
  end

  test "does not require a LivePreview module" do
    igniter = migrate(@legacy_blueprint, nil)
    assert source(igniter, @blueprint_path) =~ "trait(Brando.Trait.Blocks)"
  end

  test "applies deterministic non-Blueprint changes from the 0.54 changelog" do
    igniter = migrate(@legacy_blueprint, @legacy_live_preview)

    assert source(igniter, @brando_config_path) =~ "repo_module: LegacyApp.Repo"
    assert source(igniter, @dockerfile_path) =~ "RUN mix brando.digest"
    assert source(igniter, @dockerfile_path) =~ "RUN mix phx.digest.clean --all"
    assert source(igniter, @fonts_path) =~ "/fonts/legacy.woff2'"
    refute source(igniter, @fonts_path) =~ "/fonts/legacy.woff2?vsn=d"
    assert source(igniter, @fonts_path) =~ "/images/hero.png?vsn=d"
  end

  test "leaves the 0.55 surface to brando.migrate55" do
    igniter = migrate(@legacy_blueprint, @legacy_live_preview)

    refute source(igniter, @config_path) =~ "Swoosh.ApiClient.Req"
    assert source(igniter, @package_json_path) =~ ~s("phoenix_live_view": "~1.0.0")
    refute Map.has_key?(igniter.rewrite.sources, @florist_config_path)
    assert igniter.rms == []
  end

  test "warns instead of guessing when no Ecto Repo can be inferred" do
    files = %{
      @blueprint_path => @legacy_blueprint,
      @brando_config_path => @brando_config,
      @config_path => "import Config\n"
    }

    igniter =
      [app_name: :legacy_app, files: files]
      |> test_project_with_files()
      |> Migrate54.igniter()

    assert_has_warning(igniter, &String.contains?(&1, "no Ecto Repo was found"))
  end

  test "copies current helpers and reports the ordered manual workflow" do
    igniter = migrate(@legacy_blueprint, nil)

    assert_creates(igniter, "scripts/sync_gettext.sh", fn contents ->
      assert contents =~ "set -euo pipefail"
      refute contents =~ "gsed"
    end)

    refute_creates(igniter, "lib/mix/brando.upgrade.ex")

    assert igniter.tasks == []
    assert_has_notice(igniter, &String.contains?(&1, "Continue in this order"))
    assert_has_notice(igniter, &String.contains?(&1, "mix brando.migrate55"))
    assert_has_warning(igniter, &String.contains?(&1, "Manual 0.54 decisions remain"))
    assert_has_warning(igniter, &String.contains?(&1, "Brando.Type.Video"))
    assert_has_warning(igniter, &String.contains?(&1, "legacy ref paths"))
    assert_has_warning(igniter, &String.contains?(&1, "Vite 5 manifest"))
    assert_has_warning(igniter, &String.contains?(&1, "remaining uses in standalone Ecto schemas"))
    assert_has_warning(igniter, &String.contains?(&1, "after_export"))
    refute Enum.any?(igniter.warnings, &String.contains?(&1, "Manual 0.55 decisions"))
    refute Enum.any?(igniter.warnings, &String.contains?(&1, "Form.Primitives"))
    refute Enum.any?(igniter.notices, &String.contains?(&1, "florist.config.exs"))
  end

  test "moves Gettext backends without compiling or touching the gettext requirement" do
    mix_exs = """
    defmodule LegacyApp.MixProject do
      use Mix.Project

      def project, do: [app: :legacy_app, version: "0.1.0", deps: deps()]

      defp deps do
        [{:gettext, "~> 1.0"}]
      end
    end
    """

    igniter =
      migrate(@legacy_blueprint, nil, %{
        "mix.exs" => mix_exs,
        "lib/legacy_app_web/gettext.ex" => """
        defmodule LegacyAppWeb.Gettext do
          use Gettext, otp_app: :legacy_app
        end
        """,
        "lib/legacy_app_web/components/core.ex" => """
        defmodule LegacyAppWeb.Components.Core do
          import LegacyAppWeb.Gettext
        end
        """
      })

    assert source(igniter, "lib/legacy_app_web/gettext.ex") =~ "use Gettext.Backend, otp_app: :legacy_app"
    assert source(igniter, "lib/legacy_app_web/components/core.ex") =~ ~r/use Gettext,\s+backend: LegacyAppWeb.Gettext/
    assert source(igniter, "mix.exs") == mix_exs
    assert igniter.tasks == []
  end

  test "replaces a Gettext helper an earlier Brando shipped and keeps an edited one" do
    legacy =
      File.read!(Application.app_dir(:brando, "priv/templates/brando.migrate/legacy_sync_gettext/sync_gettext.0.54.sh"))

    current = File.read!(Application.app_dir(:brando, "priv/templates/brando.migrate/sync_gettext.sh"))

    igniter = migrate(@legacy_blueprint, nil, %{"scripts/sync_gettext.sh" => legacy})
    assert igniter.issues == []
    assert source(igniter, "scripts/sync_gettext.sh") == current

    edited = legacy <> "\necho custom\n"
    igniter = migrate(@legacy_blueprint, nil, %{"scripts/sync_gettext.sh" => edited})
    assert igniter.issues == []
    assert source(igniter, "scripts/sync_gettext.sh") == edited
    assert_has_warning(igniter, &String.contains?(&1, "differs from every version Brando shipped"))
  end

  test "removes the retired Sharp image processor from config" do
    igniter =
      migrate(@legacy_blueprint, nil, %{
        @brando_config_path => """
        import Config

        config :brando, otp_app: :legacy_app

        config :brando, Brando.Images,
          processor_module: Brando.Images.Processor.Sharp,
          default_config: %{upload_path: "images/site/default"}
        """,
        "config/prod.exs" => """
        import Config

        config :brando, Brando.Images, processor_module: Brando.Images.Processor.Sharp

        config :legacy_app, LegacyAppWeb.Endpoint, server: true
        """,
        "config/dev.exs" => """
        import Config

        config :brando, Brando.Images, processor_module: LegacyApp.Processor
        """,
        # Unformatted on purpose: files without the setting are not rewritten.
        "config/e2e.exs" => """
        import Config
        config :legacy_app, sql_sandbox: true
        config :legacy_app, LegacyAppWeb.Endpoint, server: false
        """
      })

    brando = source(igniter, @brando_config_path)
    refute brando =~ "Sharp"
    assert brando =~ ~s(default_config: %{upload_path: "images/site/default"})

    prod = source(igniter, "config/prod.exs")
    refute prod =~ "Brando.Images"
    assert prod =~ "server: true"

    # The application has no mailer, so dev.exs gets the one the task creates.
    assert source(igniter, "config/dev.exs") =~
             "config :brando, Brando.Images, processor_module: LegacyApp.Processor"

    assert_unchanged(igniter, ["config/e2e.exs"])

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate54.igniter()
    assert_unchanged(rerun, [@brando_config_path, "config/prod.exs"])
  end

  test "copied Gettext helper fills single-line translations portably" do
    directory = Path.join(System.tmp_dir!(), "brando-gettext-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    File.write!(Path.join(directory, "backend.po"), """
    msgid "Welcome"
    msgstr ""
    """)

    File.write!(Path.join(directory, "frontend.po"), """
    msgid "Welcome"
    msgstr "Hei & velkommen"
    """)

    script = Application.app_dir(:brando, ["priv", "templates", "brando.migrate", "sync_gettext.sh"])
    assert {output, 0} = System.cmd("bash", [script, directory], stderr_to_stdout: true)
    assert output =~ "Translation copy complete"
    assert File.read!(Path.join(directory, "backend.po")) =~ ~s(msgstr "Hei & velkommen")
  end

  defp migrate(blueprint, live_preview, overrides \\ %{}) do
    files =
      %{
        @blueprint_path => blueprint,
        @repo_path => @repo,
        @brando_config_path => @brando_config,
        @config_path => @config,
        @dockerfile_path => @dockerfile,
        @fonts_path => @fonts,
        @package_json_path => @package_json,
        @deployment_config_path => @deployment_config,
        @fabfile_path => @fabfile
      }
      |> Map.merge(overrides)
      |> maybe_put(@live_preview_path, live_preview)

    [app_name: :legacy_app, files: files]
    |> test_project_with_files()
    |> Migrate54.igniter()
  end

  defp test_project_with_files(opts) do
    opts
    |> test_project()
    |> include_test_files()
  end

  defp include_test_files(igniter) do
    Enum.reduce(Map.keys(igniter.assigns.test_files), igniter, fn path, igniter ->
      Igniter.include_existing_file(igniter, path)
    end)
  end

  defp source(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  defp count(content, pattern), do: content |> String.split(pattern) |> length() |> Kernel.-(1)

  defp maybe_put(files, _path, nil), do: files
  defp maybe_put(files, path, contents), do: Map.put(files, path, contents)
end
