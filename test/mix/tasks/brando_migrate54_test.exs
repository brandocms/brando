defmodule Mix.Tasks.Brando.Migrate54Test do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54

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
    end

    def list(left, right), do: {left, right}
    def list_all(_module, _language, _vars), do: []
    def list_featured(_module, _language, _vars), do: []
    def get_featured(identifiers), do: identifiers
    def get_one(module, identifier), do: {module, identifier}
    def format_date(value), do: value

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
    assert blueprint =~ "(&__MODULE__.get_one/2).(to_string(__MODULE__), identifier)"
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
    assert blueprint =~ "(&__MODULE__.format_date/1).(value)"
    assert blueprint =~ "field(:image, LegacyApp.JSONLD.ImageObject, fn entry ->"
    assert blueprint =~ "Access.key(:metadata), Access.key(:image)"
    assert blueprint =~ "field(:generated, :string, & &1.title)"
    assert blueprint =~ "field(\"title\", fn entry ->"

    assert blueprint =~
             ~r/field\(\s*\["description", "og:description"\],\s*fn entry ->/

    assert blueprint =~ "(&String.trim/1).(value)"
    assert blueprint =~ "field(\"generated\", & &1.title)"

    assert blueprint =~ "import Brando.Blueprint.Listings.Components.Core"
    assert blueprint =~ "import Brando.Blueprint.Listings.Components.Cover, only: [cover: 1]"

    assert blueprint =~
             "import Brando.Blueprint.Listings.Components.Children, only: [children_button: 1]"

    assert blueprint =~ "form do\n      default_params(%{status: :draft})"
    assert blueprint =~ "form :secondary do\n      default_params(%{status: :published})"
    assert blueprint =~ "fieldset do\n        size(:half)\n        shaded(true)"
    assert blueprint =~ "inputs_for :items do\n          cardinality(:many)\n          style(:inline)"
    refute blueprint =~ "status(:draft)"
    refute blueprint =~ "status(:published)"
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

      attribute :data, :villain

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
        <.url entry={@entry} />
        \"\"\"
      end
    end
    """

    migrated_source = legacy_blueprint |> migrate(nil) |> source(@blueprint_path)
    assert migrated_source =~ "relation(:blocks, :has_many, module: :blocks)"
    Code.compile_string(migrated_source)

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
    source = File.read!("lib/mix/tasks/brando.migrate.54.ex")

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
    assert source(igniter, @config_path) =~ "config :swoosh, api_client: Swoosh.ApiClient.Req"
    assert source(igniter, @dockerfile_path) =~ "RUN mix brando.digest"
    assert source(igniter, @dockerfile_path) =~ "RUN mix phx.digest.clean --all"
    assert source(igniter, @fonts_path) =~ "/fonts/legacy.woff2'"
    refute source(igniter, @fonts_path) =~ "/fonts/legacy.woff2?vsn=d"
    assert source(igniter, @fonts_path) =~ "/images/hero.png?vsn=d"
    live_view_version = to_string(Application.spec(:phoenix_live_view, :vsn))

    assert source(igniter, @package_json_path) =~
             ~s("phoenix_live_view": "#{live_view_version}")

    assert source(igniter, @package_json_path) =~ ~s("unrelated": "1.0.0")

    assert_creates(igniter, @florist_config_path, fn config ->
      assert {:ok, _ast} = Code.string_to_quoted(config)
      assert config =~ "project_name(\"legacy_app\")"
      assert config =~ "project_module(LegacyApp)"
      assert config =~ "set(:type, :single)"
      assert config =~ "set(:type, :nginx)"
      assert config =~ "set(:blue_port, 8055)"
      refute config =~ "legacy-secret"
      refute config =~ "legacy-ssh-secret"
    end)
  end

  test "preserves an existing Florist configuration" do
    existing_config = "use Florist.DSL\nproject_name \"already_configured\"\n"

    igniter =
      [
        app_name: :legacy_app,
        files: %{
          @deployment_config_path => @deployment_config,
          @fabfile_path => @fabfile,
          @florist_config_path => existing_config
        }
      ]
      |> test_project_with_files()
      |> Migrate54.igniter()

    assert source(igniter, @florist_config_path) == existing_config
    assert_unchanged(igniter, @florist_config_path)
  end

  test "warns without creating a Florist configuration from an incomplete legacy pair" do
    igniter =
      [app_name: :legacy_app, files: %{@deployment_config_path => @deployment_config}]
      |> test_project_with_files()
      |> Migrate54.igniter()

    refute Map.has_key?(igniter.rewrite.sources, @florist_config_path)
    assert_has_warning(igniter, &String.contains?(&1, "both legacy `deployment.cfg` and `fabfile.py` are required"))
  end

  test "preserves an explicitly configured Swoosh client" do
    existing_config = """
    import Config

    config :legacy_app, ecto_repos: [LegacyApp.Repo]
    config :swoosh, api_client: false
    """

    igniter = migrate(@legacy_blueprint, nil, %{@config_path => existing_config})
    config = source(igniter, @config_path)

    assert config =~ "config :swoosh, api_client: false"
    refute config =~ "Swoosh.ApiClient.Req"
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

    assert_creates(igniter, "lib/mix/brando.upgrade.ex", fn contents ->
      assert contents =~ "monotonically"
      refute contents =~ ":timer.sleep"
      refute contents =~ "ensure_all_started"
    end)

    assert_has_task(igniter, "igniter.update_gettext", [])
    assert_has_notice(igniter, &String.contains?(&1, "Continue in this order"))
    assert_has_warning(igniter, &String.contains?(&1, "Manual 0.54 decisions remain"))
    assert_has_warning(igniter, &String.contains?(&1, "Brando.Type.Video"))
    assert_has_warning(igniter, &String.contains?(&1, "legacy ref paths"))
    assert_has_warning(igniter, &String.contains?(&1, "Vite 5 manifest"))
    assert_has_warning(igniter, &String.contains?(&1, "*_identifiers"))
    assert_has_warning(igniter, &String.contains?(&1, "remaining uses in standalone Ecto schemas"))
    assert_has_warning(igniter, &String.contains?(&1, "after_export"))
    assert_has_warning(igniter, &String.contains?(&1, "phoenix_live_view"))
    assert_has_warning(igniter, &String.contains?(&1, "Form.Primitives"))
    assert_has_warning(igniter, &String.contains?(&1, "key_available?/2"))
    assert_has_warning(igniter, &String.contains?(&1, "config_target"))
    assert_has_warning(igniter, &String.contains?(&1, "oban_job_state"))
    assert_has_warning(igniter, &String.contains?(&1, "Database passwords are intentionally not written"))
    assert_has_notice(igniter, &String.contains?(&1, "Created `florist.config.exs`"))
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
