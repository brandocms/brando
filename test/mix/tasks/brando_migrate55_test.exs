defmodule Mix.Tasks.Brando.Migrate55Test do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.Brando.Migrate54
  alias Mix.Tasks.Brando.Migrate55

  @blueprint_path "lib/legacy_app/projects/project.ex"
  @repo_path "lib/legacy_app/repo.ex"
  @brando_config_path "config/brando.exs"
  @config_path "config/config.exs"
  @package_json_path "assets/package.json"
  @vite_config_path "assets/frontend/vite.config.js"
  @deployment_config_path "deployment.cfg"
  @fabfile_path "fabfile.py"
  @florist_config_path "florist.config.exs"
  @gettext_script_path "scripts/sync_gettext.sh"
  @legacy_task_path "lib/mix/brando.upgrade.ex"
  @archive_path "priv/brando/legacy_tasks/brando.upgrade.ex.disabled"
  @legacy_templates "priv/templates/brando.migrate/legacy_upgrade_tasks"

  # A Blueprint as `mix brando.migrate54` on Brando 0.54 left it: 0.54 syntax
  # throughout, but a custom listing row that still relies on implicit imports.
  @blueprint_054 """
  defmodule LegacyApp.Projects.Project do
    use Brando.Blueprint,
      application: "LegacyApp",
      domain: "Projects",
      schema: "Project",
      singular: "project",
      plural: "projects"

    trait Brando.Trait.Blocks

    attribute :title, :string

    relations do
      relation :blocks, :has_many, module: :blocks
    end

    datasources do
      datasource :all do
        type :list
        list {__MODULE__, :list_all, [status: :published]}
      end
    end

    listings do
      listing do
        query %{order: "asc title"}
        filter label: "Title", key: "title"
        component &__MODULE__.listing_row/1
      end
    end

    forms do
      form do
        default_params %{status: :draft}

        fieldset do
          input :title, :text
        end
      end
    end

    def list_all(_module, _language, _vars), do: []

    def listing_row(assigns) do
      ~H\"""
      <.cover image={@entry.cover} />
      <.update_link entry={@entry}>{@entry.title}</.update_link>
      \"""
    end
  end
  """

  @blueprint_053 """
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

    datasources do
      list :all, {__MODULE__, :list_all, [status: :published]}
    end

    listings do
      listing do
        listing_query %{order: "asc title"}
        filters [[label: "Title", filter: "title"]]
        component &__MODULE__.listing_row/1
      end
    end

    forms do
      form default_params: %{status: :draft} do
        fieldset [size: :half] do
          input :title, :text
        end
      end
    end

    def list_all(_module, _language, _vars), do: []

    def listing_row(assigns) do
      ~H\"""
      <.update_link entry={@entry}>{@entry.title}</.update_link>
      \"""
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
    otp_app: :legacy_app,
    repo_module: LegacyApp.Repo
  """

  @config """
  import Config

  config :legacy_app, ecto_repos: [LegacyApp.Repo]
  """

  @package_json """
  {
    "dependencies": {
      "phoenix_live_view": "1.0.18",
      "unrelated": "1.0.0"
    }
  }
  """

  @vite_config """
  export default defineConfig({
    css: { devSourcemap: true },
    build: {
      sourcemap: true, // we want to debug our code in production
    },
  })
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

  test "upgrades an application that 0.54 left behind without blocking issues" do
    igniter = migrate(@blueprint_054)
    blueprint = source(igniter, @blueprint_path)

    assert igniter.issues == []

    assert blueprint =~ "import Brando.Blueprint.Listings.Components.Core"
    assert blueprint =~ "import Brando.Blueprint.Listings.Components.Cover, only: [cover: 1]"
    refute blueprint =~ "Listings.Components.Children"
    assert blueprint =~ ~r/type[ (]:list/
    assert blueprint =~ ~r/trait[ (]Brando\.Trait\.Blocks/

    assert source(igniter, @config_path) =~ "config :swoosh, api_client: Swoosh.ApiClient.Req"
    live_view_version = to_string(Application.spec(:phoenix_live_view, :vsn))

    assert source(igniter, @package_json_path) =~
             ~s("phoenix_live_view": "#{live_view_version}")

    assert source(igniter, @package_json_path) =~ ~s("unrelated": "1.0.0")

    vite_config = source(igniter, @vite_config_path)
    assert vite_config =~ "sourcemap: 'hidden', // we want"
    assert vite_config =~ "devSourcemap: true"

    assert_creates(igniter, @florist_config_path, fn config ->
      assert config =~ "project_name(\"legacy_app\")"
      refute config =~ "legacy-secret"
    end)

    script = source(igniter, @gettext_script_path)
    assert script =~ "set -euo pipefail"
    refute script =~ "Processing file:"

    assert_rms(igniter, @legacy_task_path)
    assert_creates(igniter, @archive_path, fn archive -> assert archive == legacy_task("0.54") end)
  end

  test "is idempotent" do
    first_pass = migrate(@blueprint_054)

    second_pass =
      first_pass
      |> apply_igniter!()
      |> include_test_files()
      |> Migrate55.igniter()

    assert second_pass.issues == []
    assert_unchanged(second_pass)
    assert_has_notice(second_pass, &String.contains?(&1, "No consumer-owned brando.upgrade task"))
  end

  test "continues from migrate54 on 0.53 source without blocking issues" do
    igniter =
      @blueprint_053
      |> migrate_files(%{@legacy_task_path => nil, @gettext_script_path => nil})
      |> Migrate54.igniter()
      |> apply_igniter!()
      |> include_test_files()
      |> Migrate55.igniter()

    assert igniter.issues == []
    blueprint = source(igniter, @blueprint_path)
    assert blueprint =~ "import Brando.Blueprint.Listings.Components.Core"
    assert blueprint =~ "trait(Brando.Trait.Blocks)"
    assert_unchanged(igniter, @gettext_script_path)
    assert_has_notice(igniter, &String.contains?(&1, "No consumer-owned brando.upgrade task"))
  end

  test "recognizes every upgrade task Brando ever installed" do
    igniter = migrate(@blueprint_054, %{@legacy_task_path => legacy_task("0.55-dev")})

    assert igniter.issues == []
    assert_rms(igniter, @legacy_task_path)
  end

  test "blocks instead of discarding a customized upgrade task" do
    customized = String.replace(legacy_task("0.54"), "def run(_) do", "def run(_) do\n    IO.puts(\"custom\")")
    igniter = migrate(@blueprint_054, %{@legacy_task_path => customized})

    assert Enum.any?(igniter.issues, &String.contains?(&1, "customized or unrecognized"))
    assert igniter.rms == []
  end

  test "preserves an existing Florist configuration" do
    existing_config = "use Florist.DSL\nproject_name \"already_configured\"\n"
    igniter = migrate(@blueprint_054, %{@florist_config_path => existing_config})

    assert source(igniter, @florist_config_path) == existing_config
    assert_unchanged(igniter, @florist_config_path)
  end

  test "warns without creating a Florist configuration from an incomplete legacy pair" do
    igniter = migrate(@blueprint_054, %{@fabfile_path => nil})

    refute Map.has_key?(igniter.rewrite.sources, @florist_config_path)
    assert_has_warning(igniter, &String.contains?(&1, "both legacy `deployment.cfg` and `fabfile.py` are required"))
  end

  test "preserves an explicitly configured Swoosh client" do
    existing_config = """
    import Config

    config :legacy_app, ecto_repos: [LegacyApp.Repo]
    config :swoosh, api_client: false
    """

    config = @blueprint_054 |> migrate(%{@config_path => existing_config}) |> source(@config_path)

    assert config =~ "config :swoosh, api_client: false"
    refute config =~ "Swoosh.ApiClient.Req"
  end

  test "starts the endpoint last, so it drains its sockets before presence stops" do
    application = """
    defmodule LegacyApp.Application do
      use Application

      def start(_type, _args) do
        children = [
          LegacyApp.Repo,
          # Start the endpoint
          LegacyAppWeb.Endpoint,
          {Phoenix.PubSub, name: LegacyApp.PubSub},
          LegacyApp.Presence,
          Brando
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end
    end
    """

    igniter = migrate(@blueprint_054, %{"lib/legacy_app/application.ex" => application})
    upgraded = source(igniter, "lib/legacy_app/application.ex")

    assert [_, after_brando] = String.split(upgraded, ~r/^\s*Brando,?$/m, parts: 2)
    assert after_brando =~ "# Start the endpoint\n"
    assert after_brando =~ "LegacyAppWeb.Endpoint"
    assert upgraded =~ ~r/LegacyApp\.Repo,\s+\{Phoenix\.PubSub/
  end

  test "the Florist conversion reads the legacy .envrc, nginx and supervisord files" do
    igniter =
      migrate(@blueprint_054, %{
        @deployment_config_path => String.replace(@deployment_config, "https://example.com", "http://somesite.com"),
        ".envrc.prod" => ~s(export BRANDO_URL_HOST="www.legacy-app.no"\nexport BRANDO_URL_PORT="443"\n),
        "etc/supervisord/prod.conf" => ~s([program:legacy_app_prod]\nenvironment=PORT="8123"\n)
      })

    assert_creates(igniter, @florist_config_path, fn config ->
      assert config =~ ~s(set(:domain, "www.legacy-app.no"\))
      assert config =~ "set(:blue_port, 8123)"
    end)

    assert_has_warning(igniter, &String.contains?(&1, "from .envrc.prod (BRANDO_URL_HOST)"))
    assert_has_warning(igniter, &String.contains?(&1, "runs under supervisord"))
  end

  test "adds the health plug Florist checks to the endpoint, before the router" do
    endpoint_path = "lib/legacy_app_web/endpoint.ex"

    endpoint = """
    defmodule LegacyAppWeb.Endpoint do
      use Phoenix.Endpoint, otp_app: :legacy_app

      plug Plug.Session, @session_options
      plug LegacyAppWeb.Router
    end
    """

    igniter = migrate(@blueprint_054, %{endpoint_path => endpoint})
    # The test project's formatter has no Phoenix locals_without_parens.
    assert source(igniter, endpoint_path) =~
             ~r/plug\(?Plug.Session, @session_options\)?\n\s*plug\(?Brando.Plug.Health\)?\n\s*plug\(?LegacyAppWeb.Router/

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
    assert_unchanged(rerun, endpoint_path)

    # An endpoint that already has the plug is not rewritten (or reformatted).
    has_plug =
      "defmodule LegacyAppWeb.Endpoint do\n  use Phoenix.Endpoint, otp_app: :legacy_app\n  plug Brando.Plug.Health\n  plug LegacyAppWeb.Router\nend\n"

    assert_unchanged(migrate(@blueprint_054, %{endpoint_path => has_plug}), endpoint_path)

    # Only when the task creates the Florist configuration.
    existing = migrate(@blueprint_054, %{endpoint_path => endpoint, @florist_config_path => "use Florist.DSL\n"})
    assert_unchanged(existing, endpoint_path)
  end

  test "points Brando at the application's mailer" do
    mailer = "defmodule LegacyApp.Mailer do\n  use Swoosh.Mailer, otp_app: :legacy_app\nend\n"
    igniter = migrate(@blueprint_054, %{"lib/legacy_app/mailer.ex" => mailer})

    assert source(igniter, @brando_config_path) =~ "mailer: LegacyApp.Mailer"
    assert_has_warning(igniter, &String.contains?(&1, "config :brando, Brando.Mailer, from:"))
  end

  test "leaves the mailer alone when the application has none, or has chosen one" do
    assert_unchanged(migrate(@blueprint_054), @brando_config_path)

    chosen = @brando_config <> "\nconfig :brando, mailer: LegacyApp.Notifications.Mailer\n"
    mailer = "defmodule LegacyApp.Mailer do\n  use Swoosh.Mailer, otp_app: :legacy_app\nend\n"
    igniter = migrate(@blueprint_054, %{"lib/legacy_app/mailer.ex" => mailer, @brando_config_path => chosen})
    assert_unchanged(igniter, @brando_config_path)
  end

  describe "modules renamed in 0.55" do
    @router_path "lib/legacy_app_web/router.ex"
    @notify_path "lib/legacy_app/notify.ex"

    @router """
    defmodule LegacyAppWeb.Router do
      use LegacyAppWeb, :router

      scope "/" do
        pipe_through :browser
        get "/robots.txt", Brando.SEOController, :robots
        get "/__p__/:preview_key", Brando.PreviewController, :show
        get "/sitemaps/:file", Brando.SitemapController, :show
      end
    end
    """

    @notify """
    defmodule LegacyApp.Notify do
      alias Brando.UserChannel
      alias Brando.{LobbyChannel, Utils}

      def done(user), do: UserChannel.alert(user, Utils.slugify("Done"))
      def lobby, do: LobbyChannel
      def unrelated, do: {LegacyApp.UserChannel, UserChannelHelper}
    end
    """

    test "points routers, sockets, config and code at the new names" do
      config =
        @config <> "\nconfig :legacy_app, LegacyAppWeb.Endpoint, render_errors: [formats: [html: Brando.ErrorHTML]]\n"

      igniter = migrate(@blueprint_054, %{@router_path => @router, @notify_path => @notify, @config_path => config})

      assert igniter.issues == []
      router = source(igniter, @router_path)
      assert router =~ ~s(get "/robots.txt", BrandoWeb.SEOController, :robots)
      assert router =~ ~s(get "/__p__/:preview_key", BrandoWeb.PreviewController, :show)
      assert router =~ ~s(get "/sitemaps/:file", BrandoWeb.SitemapController, :show)
      assert source(igniter, @config_path) =~ "html: BrandoWeb.ErrorHTML"

      notify = source(igniter, @notify_path)
      assert notify =~ "alias BrandoAdmin.UserChannel"
      assert notify =~ "UserChannel.alert(user"
      assert notify =~ "{LegacyApp.UserChannel, UserChannelHelper}"

      # Brando.LobbyChannel left Brando's namespace: the braces can't hold it
      assert notify =~ "alias Brando.{LobbyChannel, Utils}"

      assert_has_warning(igniter, fn warning ->
        String.contains?(warning, @notify_path) and String.contains?(warning, "BrandoAdmin.LobbyChannel")
      end)
    end

    test "the short name follows Brando.Upload to Brando.Uploads.Store, unless it is taken" do
      uploader = """
      defmodule LegacyApp.Uploader do
        alias Brando.Upload

        def store(meta, entry, cfg, user), do: Upload.handle_upload(meta, entry, cfg, user)
        def plug, do: Plug.Upload
        def uploads, do: Brando.Uploads
      end
      """

      taken = """
      defmodule LegacyApp.Shop do
        alias Brando.Upload
        alias LegacyApp.Store

        def store(meta, entry, cfg, user), do: {Store, Upload.handle_upload(meta, entry, cfg, user)}
      end
      """

      igniter = migrate(@blueprint_054, %{"lib/legacy_app/uploader.ex" => uploader, "lib/legacy_app/shop.ex" => taken})
      assert igniter.issues == []

      assert source(igniter, "lib/legacy_app/uploader.ex") == """
             defmodule LegacyApp.Uploader do
               alias Brando.Uploads.Store

               def store(meta, entry, cfg, user), do: Store.handle_upload(meta, entry, cfg, user)
               def plug, do: Plug.Upload
               def uploads, do: Brando.Uploads
             end
             """

      assert source(igniter, "lib/legacy_app/shop.ex") == """
             defmodule LegacyApp.Shop do
               alias Brando.Uploads.Store, as: Upload
               alias LegacyApp.Store

               def store(meta, entry, cfg, user), do: {Store, Upload.handle_upload(meta, entry, cfg, user)}
             end
             """
    end

    test "routes inside a scope with an alias are read relative to it" do
      router = """
      defmodule LegacyAppWeb.Router do
        use LegacyAppWeb, :router

        scope "/", Brando do
          pipe_through :browser
          get "/robots.txt", SEOController, :robots
          get "/sitemaps/:file", SitemapController, :show, as: :sitemap
          get "/legacy", Upload, :show

          scope "/p", alias: false do
            get "/:key", PreviewController, :show
          end
        end

        scope "/", LegacyAppWeb do
          get "/__p__/:preview_key", Brando.PreviewController, :show
        end
      end
      """

      igniter = migrate(@blueprint_054, %{@router_path => router})
      assert igniter.issues == []

      assert source(igniter, @router_path) == """
             defmodule LegacyAppWeb.Router do
               use LegacyAppWeb, :router

               scope "/", Brando do
                 pipe_through :browser
                 get "/robots.txt", BrandoWeb.SEOController, :robots, alias: false
                 get "/sitemaps/:file", BrandoWeb.SitemapController, :show, as: :sitemap, alias: false
                 get "/legacy", Uploads.Store, :show

                 scope "/p", alias: false do
                   get "/:key", PreviewController, :show
                 end
               end

               scope "/", LegacyAppWeb do
                 get "/__p__/:preview_key", Brando.PreviewController, :show
               end
             end
             """
    end

    test "aliases are resolved per module" do
      two_modules = """
      defmodule LegacyApp.A do
        alias Brando.Upload
        def store(m, e, c, u), do: Upload.handle_upload(m, e, c, u)
      end

      defmodule LegacyApp.B do
        alias LegacyApp.Upload
        def own, do: Upload.new()

        defmodule Inner do
          def own, do: Upload.new()
        end
      end

      defmodule LegacyApp.C do
        alias Brando.Meta
        def tags(conn), do: Meta.HTML.render_meta(conn)
      end
      """

      path = "lib/legacy_app/two_modules.ex"
      igniter = migrate(@blueprint_054, %{path => two_modules})
      assert igniter.issues == []

      # Meta.HTML kept its name: the alias stays, so nothing goes unused
      assert source(igniter, path) == """
             defmodule LegacyApp.A do
               alias Brando.Uploads.Store
               def store(m, e, c, u), do: Store.handle_upload(m, e, c, u)
             end

             defmodule LegacyApp.B do
               alias LegacyApp.Upload
               def own, do: Upload.new()

               defmodule Inner do
                 def own, do: Upload.new()
               end
             end

             defmodule LegacyApp.C do
               alias Brando.Meta
               def tags(conn), do: Meta.HTML.render_meta(conn)
             end
             """
    end

    test "a scoped route keeps its layout and comments, and alias: false goes after its last argument" do
      router = """
      defmodule LegacyAppWeb.Router do
        alias Brando, as: B

        scope "/", Brando do
          get "/r5",
              SEOController,
              :robots,
              # keep me
              private: %{a: 1}

          get "/r6", SitemapController, :show # trailing
        end

        scope "/", B do
          get "/r7", PreviewController, :show
        end

        scope "/", Brando, alias: false do
          get "/r8", SEOController, :robots
        end
      end
      """

      igniter = migrate(@blueprint_054, %{@router_path => router})
      assert igniter.issues == []

      expected = """
      defmodule LegacyAppWeb.Router do
        alias Brando, as: B

        scope "/", Brando do
          get "/r5",
              BrandoWeb.SEOController,
              :robots,
              # keep me
              private: %{a: 1}, alias: false

          get "/r6", BrandoWeb.SitemapController, :show, alias: false # trailing
        end

        scope "/", B do
          get "/r7", BrandoWeb.PreviewController, :show, alias: false
        end

        scope "/", Brando, alias: false do
          get "/r8", BrandoWeb.SEOController, :robots, alias: false
        end
      end
      """

      assert source(igniter, @router_path) == expected
      assert {:ok, _} = Code.string_to_quoted(expected)
      assert_idempotent(igniter, @router_path)
    end

    test "scoped routes it cannot safely rewrite are left as they are, and reported" do
      router = """
      defmodule LegacyAppWeb.Router do
        @opts [as: :seo]

        scope "/", Brando do
          forward "/f", SEOController
          resources "/r", SitemapController
          match :get, "/m", PreviewController, :show
          get "/b", SEOController, :robots, [as: :robots]
          get "/a", SEOController, :robots, @opts
          get "/t", SEOController, :robots, alias: true
        end
      end
      """

      igniter = migrate(@blueprint_054, %{@router_path => router})
      assert igniter.issues == []
      assert source(igniter, @router_path) == router

      for line <- 5..10 do
        assert_has_warning(igniter, fn warning ->
          String.contains?(warning, "#{@router_path}:#{line} routes to Brando.") and
            String.contains?(warning, "add `alias: false`")
        end)
      end
    end

    test "a scoped route whose last argument is parenthesised or computed is left and reported" do
      router = """
      defmodule LegacyAppWeb.Router do
        scope "/", Brando do
          get "/p", PreviewController, (:show)
          get "/s", SitemapController, :show, as: (:sitemap)
          get "/i", SEOController, :robots, private: (if true, do: %{}, else: %{})
          get "/d", SEOController, :robots, do: :x
        end
      end
      """

      igniter = migrate(@blueprint_054, %{@router_path => router})
      assert igniter.issues == []
      assert source(igniter, @router_path) == router

      for line <- 3..6 do
        assert_has_warning(igniter, &String.contains?(&1, "#{@router_path}:#{line} routes to Brando."))
      end
    end

    test "a relative alias under a renamed module, a nested defmodule's name and an alias in a function" do
      code = """
      defmodule LegacyApp.Relative do
        alias Brando.Meta
        alias Meta.HTML

        def f, do: {%Meta{}, HTML.render(1)}
      end

      defmodule LegacyApp.RelativeOnly do
        alias Brando.Meta
        alias Meta.HTML

        def f, do: HTML.render(1)
      end

      defmodule LegacyApp.Shadow do
        alias Brando.Upload

        defmodule Store do
          def x(_), do: :mine
        end

        def f(u), do: Upload.x(u)
      end

      defmodule LegacyApp.InFunction do
        def f(u) do
          alias Brando.Upload
          Upload.x(u)
        end

        def g, do: Upload.y()
      end
      """

      path = "lib/legacy_app/relative.ex"
      igniter = migrate(@blueprint_054, %{path => code})
      assert igniter.issues == []

      assert source(igniter, path) == """
             defmodule LegacyApp.Relative do
               alias Brando.Sites.Meta
               alias Brando.Meta.HTML

               def f, do: {%Meta{}, HTML.render(1)}
             end

             defmodule LegacyApp.RelativeOnly do
               alias Brando.Meta
               alias Meta.HTML

               def f, do: HTML.render(1)
             end

             defmodule LegacyApp.Shadow do
               alias Brando.Uploads.Store, as: Upload

               defmodule Store do
                 def x(_), do: :mine
               end

               def f(u), do: Upload.x(u)
             end

             defmodule LegacyApp.InFunction do
               def f(u) do
                 alias Brando.Upload
                 Upload.x(u)
               end

               def g, do: Upload.y()
             end
             """

      assert_has_warning(igniter, &String.contains?(&1, "#{path}:27 aliases Brando.Upload inside a function"))
      assert_idempotent(igniter, path)
    end

    test "an alias that nested modules use is decided by every use" do
      nested = """
      defmodule LegacyApp.Outer do
        alias Brando.Meta
        alias Brando.Upload

        def meta, do: %Meta{}

        defmodule Inner do
          alias Other.Store

          def tags(conn), do: Meta.HTML.render_meta(conn)
          def store(m, e, c, u), do: {Store, Upload.handle_upload(m, e, c, u)}
        end
      end

      defmodule LegacyApp.OnlyInner do
        alias Brando.Meta

        defmodule Inner do
          def tags(conn), do: Meta.HTML.render_meta(conn)
        end
      end
      """

      path = "lib/legacy_app/nested.ex"
      igniter = migrate(@blueprint_054, %{path => nested})
      assert igniter.issues == []

      assert source(igniter, path) == """
             defmodule LegacyApp.Outer do
               alias Brando.Sites.Meta
               alias Brando.Uploads.Store, as: Upload

               def meta, do: %Meta{}

               defmodule Inner do
                 alias Other.Store

                 def tags(conn), do: Brando.Meta.HTML.render_meta(conn)
                 def store(m, e, c, u), do: {Store, Upload.handle_upload(m, e, c, u)}
               end
             end

             defmodule LegacyApp.OnlyInner do
               alias Brando.Meta

               defmodule Inner do
                 def tags(conn), do: Meta.HTML.render_meta(conn)
               end
             end
             """

      assert_idempotent(igniter, path)
    end

    test "an as: alias is followed into the modules under it" do
      as_aliases = """
      defmodule LegacyApp.Tags do
        alias Brando.Meta, as: M

        def tags(conn), do: M.HTML.render_meta(conn)
      end

      defmodule LegacyApp.Both do
        alias Brando.Meta, as: M

        def meta, do: %M{}
        def tags(conn), do: M.HTML.render_meta(conn)
      end
      """

      path = "lib/legacy_app/as_aliases.ex"
      igniter = migrate(@blueprint_054, %{path => as_aliases})
      assert igniter.issues == []

      assert source(igniter, path) == """
             defmodule LegacyApp.Tags do
               alias Brando.Meta, as: M

               def tags(conn), do: M.HTML.render_meta(conn)
             end

             defmodule LegacyApp.Both do
               alias Brando.Sites.Meta, as: M

               def meta, do: %M{}
               def tags(conn), do: Brando.Meta.HTML.render_meta(conn)
             end
             """

      assert_idempotent(igniter, path)
    end

    test "the Identity's schemas move under Brando.Sites, and Brando.Meta.HTML stays" do
      identity = """
      defmodule LegacyApp.Identity do
        alias Brando.Meta
        alias Brando.{Link, Utils}

        def links, do: [%Link{name: "Instagram", url: "https://instagram.com"}, %Brando.Config{}]
        def meta, do: %Meta{key: "a", value: Utils.slugify("b")}
        def tags(conn), do: {Brando.Meta.HTML.render_meta(conn), Meta.HTML.render_meta(conn)}
        def plug, do: Plug.Upload
      end
      """

      path = "lib/legacy_app/identity.ex"
      igniter = migrate(@blueprint_054, %{path => identity})
      assert igniter.issues == []

      assert source(igniter, path) == """
             defmodule LegacyApp.Identity do
               alias Brando.Sites.Meta
               alias Brando.{Sites.Link, Utils}

               def links, do: [%Link{name: "Instagram", url: "https://instagram.com"}, %Brando.Sites.Config{}]
               def meta, do: %Meta{key: "a", value: Utils.slugify("b")}
               def tags(conn), do: {Brando.Meta.HTML.render_meta(conn), Brando.Meta.HTML.render_meta(conn)}
               def plug, do: Plug.Upload
             end
             """
    end

    test "an alias inside a function, or after a use, only reaches the code after it" do
      code = """
      defmodule LegacyApp.Files do
        alias Brando.Upload

        def store(m, e, c, u), do: Upload.handle_upload(m, e, c, u)

        def plug_upload(path) do
          alias Plug.Upload
          %Upload{path: path}
        end

        def both(path) do
          Upload.handle_upload(path, nil, nil, nil)
          alias Plug.Upload
          %Upload{path: path}
        end

        def after_both, do: %Upload{}
      end

      defmodule LegacyApp.Later do
        def before, do: Upload.x()
        alias Brando.Upload
        def later, do: Upload.y()
      end
      """

      path = "lib/legacy_app/files.ex"
      igniter = migrate(@blueprint_054, %{path => code})
      assert igniter.issues == []

      expected = """
      defmodule LegacyApp.Files do
        alias Brando.Uploads.Store

        def store(m, e, c, u), do: Store.handle_upload(m, e, c, u)

        def plug_upload(path) do
          alias Plug.Upload
          %Upload{path: path}
        end

        def both(path) do
          Store.handle_upload(path, nil, nil, nil)
          alias Plug.Upload
          %Upload{path: path}
        end

        def after_both, do: %Store{}
      end

      defmodule LegacyApp.Later do
        def before, do: Upload.x()
        alias Brando.Uploads.Store
        def later, do: Store.y()
      end
      """

      assert source(igniter, path) == expected
      assert {:ok, _} = Code.string_to_quoted(expected)
      assert_idempotent(igniter, path)

      # The doctor reads the original the same way: the Plug structs are not Brando.Upload
      assert [{4, "Brando.Upload"}, {12, "Brando.Upload"}, {17, "Brando.Upload"}, {23, "Brando.Upload"}] =
               doctor_findings(code)
    end

    test "the same short name aliased twice in a module: each alias keeps its own uses" do
      code = """
      defmodule LegacyApp.Attachments do
        alias Plug.Upload

        def from_path(path), do: %Upload{path: path}

        alias Brando.Upload

        def store(m, e, c, u), do: Upload.handle_upload(m, e, c, u)
      end
      """

      path = "lib/legacy_app/attachments.ex"
      igniter = migrate(@blueprint_054, %{path => code})
      assert igniter.issues == []

      expected = """
      defmodule LegacyApp.Attachments do
        alias Plug.Upload

        def from_path(path), do: %Upload{path: path}

        alias Brando.Uploads.Store

        def store(m, e, c, u), do: Store.handle_upload(m, e, c, u)
      end
      """

      assert source(igniter, path) == expected
      assert {:ok, _} = Code.string_to_quoted(expected)
      assert_idempotent(igniter, path)
      assert [{8, "Brando.Upload"}] = doctor_findings(code)
    end

    test "a scope's alias is read from its own module, where the scope is declared" do
      router = """
      defmodule LegacyAppWeb.Router do
        use LegacyAppWeb, :router
        alias LegacyAppWeb, as: B

        scope "/", B do
          get "/robots.txt", SEOController, :robots
        end
      end

      defmodule LegacyAppWeb.LaterRouter do
        use LegacyAppWeb, :router

        scope "/", B do
          get "/robots.txt", SEOController, :robots
        end

        alias Brando, as: B
        def slug(s), do: B.Utils.slugify(s)
      end

      defmodule LegacyApp.Later do
        alias Brando, as: B
        def slug(s), do: B.Utils.slugify(s)
      end
      """

      igniter = migrate(@blueprint_054, %{@router_path => router})
      assert igniter.issues == []
      assert source(igniter, @router_path) == router
      refute Enum.any?(igniter.warnings, &String.contains?(&1, @router_path))
      assert doctor_findings(router) == []
    end

    test "a brace alias under a renamed module's alias is spelled out" do
      code = """
      defmodule LegacyApp.Braced do
        alias Brando.Meta
        alias Meta.{HTML}

        def meta, do: %Meta{}
        def tags(assigns), do: HTML.render_meta(assigns)
      end

      defmodule LegacyApp.BracedOnly do
        alias Brando.Meta
        alias Meta.{HTML}

        def tags(assigns), do: HTML.render_meta(assigns)
      end
      """

      path = "lib/legacy_app/braced.ex"
      igniter = migrate(@blueprint_054, %{path => code})
      assert igniter.issues == []

      expected = """
      defmodule LegacyApp.Braced do
        alias Brando.Sites.Meta
        alias Brando.Meta.{HTML}

        def meta, do: %Meta{}
        def tags(assigns), do: HTML.render_meta(assigns)
      end

      defmodule LegacyApp.BracedOnly do
        alias Brando.Meta
        alias Meta.{HTML}

        def tags(assigns), do: HTML.render_meta(assigns)
      end
      """

      assert source(igniter, path) == expected
      assert {:ok, _} = Code.string_to_quoted(expected)
      assert_idempotent(igniter, path)
      assert doctor_findings(expected) == []
    end

    test "a rewrite that would change what another module name means leaves the file, and reports it" do
      code = """
      defmodule LegacyApp.ShadowedNamespace do
        alias Brando.Meta
        alias LegacyApp.Brando

        def meta, do: %Meta{}
        def tags(conn), do: Meta.HTML.render_meta(conn)
        def own, do: Brando.thing()
      end
      """

      path = "lib/legacy_app/shadowed_namespace.ex"
      igniter = migrate(@blueprint_054, %{path => code})
      assert igniter.issues == []
      assert source(igniter, path) == code

      assert_has_warning(igniter, fn warning ->
        String.contains?(warning, "#{path}:6") and String.contains?(warning, "the file is unchanged")
      end)

      assert [{5, "Brando.Meta"}] = doctor_findings(code)
    end

    test "an alias declared in another macro's block may reach past it, so the file is left and reported" do
      code = """
      defmodule LegacyApp.Dsl do
        alias Brando.Upload

        settings do
          alias Plug.Upload
        end

        def f, do: %Upload{}
      end
      """

      path = "lib/legacy_app/dsl.ex"
      igniter = migrate(@blueprint_054, %{path => code})
      assert igniter.issues == []
      assert source(igniter, path) == code
      assert_has_warning(igniter, &String.contains?(&1, "#{path}:8 names modules renamed in 0.55"))
      assert [{8, "Brando.Upload"}] = doctor_findings(code)
    end

    test "each block of if, try, def and with keeps its own aliases" do
      code = """
      defmodule LegacyApp.Branches do
        alias Brando.Upload

        def f(x) do
          if x do
            alias Plug.Upload
            Upload.foo()
          else
            %Upload{}
          end
        end

        def g do
          alias Plug.Upload
          %Upload{}
        rescue
          _ -> Upload.x()
        end

        def h(x) do
          try do
            alias Plug.Upload
            %Upload{}
          rescue
            _ -> Upload.x()
          after
            Upload.y()
          end
        end

        def i(x) do
          with {:ok, y} <- x do
            alias Plug.Upload
            %Upload{path: y}
          else
            _ -> Upload.x()
          end
        end
      end
      """

      path = "lib/legacy_app/branches.ex"
      igniter = migrate(@blueprint_054, %{path => code})
      assert igniter.issues == []

      expected = """
      defmodule LegacyApp.Branches do
        alias Brando.Uploads.Store

        def f(x) do
          if x do
            alias Plug.Upload
            Upload.foo()
          else
            %Store{}
          end
        end

        def g do
          alias Plug.Upload
          %Upload{}
        rescue
          _ -> Store.x()
        end

        def h(x) do
          try do
            alias Plug.Upload
            %Upload{}
          rescue
            _ -> Store.x()
          after
            Store.y()
          end
        end

        def i(x) do
          with {:ok, y} <- x do
            alias Plug.Upload
            %Upload{path: y}
          else
            _ -> Store.x()
          end
        end
      end
      """

      assert source(igniter, path) == expected
      assert {:ok, _} = Code.string_to_quoted(expected)
      assert_idempotent(igniter, path)
      assert [{9, _}, {17, _}, {25, _}, {27, _}, {36, _}] = doctor_findings(code)
    end

    test "an alias in a remote macro's do block may reach past it, so the file is left and reported" do
      code = """
      defmodule LegacyApp.RemoteDsl do
        alias Brando.Upload

        Some.Dsl.settings do
          alias Plug.Upload
        end

        Kernel.if true do
          alias Plug.Upload
        end

        def f, do: %Upload{}
      end
      """

      path = "lib/legacy_app/remote_dsl.ex"
      igniter = migrate(@blueprint_054, %{path => code})
      assert igniter.issues == []
      assert source(igniter, path) == code
      assert_has_warning(igniter, &String.contains?(&1, "#{path}:12 names modules renamed in 0.55"))
      assert [{12, "Brando.Upload"}] = doctor_findings(code)
    end

    test "a template that names a renamed alias leaves the file, and is reported" do
      code = ~S'''
      defmodule LegacyAppWeb.Head do
        use Phoenix.Component
        alias Brando.Meta

        def meta, do: %Meta{}

        def head(assigns) do
          ~H"""
          <title>{@title}</title>
          <Meta.HTML.render_meta conn={@conn} />
          """
        end
      end
      '''

      embedded = """
      defmodule LegacyAppWeb.Layouts do
        use Phoenix.Component
        alias Brando.Upload

        def store(m, e, c, u), do: Upload.handle_upload(m, e, c, u)

        embed_templates "layouts/*"
      end
      """

      template = """
      <main>
        {Upload.url(@upload)}
      </main>
      """

      head_path = "lib/legacy_app_web/head.ex"
      layouts_path = "lib/legacy_app_web/layouts.ex"

      files = %{
        head_path => code,
        layouts_path => embedded,
        "lib/legacy_app_web/layouts/app.html.heex" => template
      }

      igniter = migrate(@blueprint_054, files)
      assert igniter.issues == []
      assert source(igniter, head_path) == code
      assert source(igniter, layouts_path) == embedded
      assert_has_warning(igniter, &String.contains?(&1, "#{head_path}:10 names modules renamed in 0.55"))
      assert_has_warning(igniter, &String.contains?(&1, "#{layouts_path}:7 names modules renamed in 0.55"))
      assert [{5, "Brando.Meta"}] = doctor_findings(code)
    end

    test "templates whose pattern or root is computed cannot be read, so the file is left and reported" do
      computed = """
      defmodule LegacyAppWeb.Computed do
        use Phoenix.Component
        alias Brando.Upload

        @pattern "computed/*"
        def store(m, e, c, u), do: Upload.handle_upload(m, e, c, u)

        embed_templates @pattern
      end
      """

      rooted = """
      defmodule LegacyAppWeb.Rooted do
        use Phoenix.Component
        alias Brando.Upload

        def store(m, e, c, u), do: Upload.handle_upload(m, e, c, u)

        embed_templates "rooted/*", root: Path.join(__DIR__, "x")
      end
      """

      files = %{
        "lib/legacy_app_web/computed.ex" => computed,
        "lib/legacy_app_web/rooted.ex" => rooted,
        "lib/legacy_app_web/computed/c.html.heex" => "{Upload.url(@x)}\n"
      }

      igniter = migrate(@blueprint_054, files)
      assert igniter.issues == []
      assert source(igniter, "lib/legacy_app_web/computed.ex") == computed
      assert source(igniter, "lib/legacy_app_web/rooted.ex") == rooted
      assert_has_warning(igniter, &String.contains?(&1, "lib/legacy_app_web/computed.ex:8 names modules renamed in 0.55"))
      assert_has_warning(igniter, &String.contains?(&1, "lib/legacy_app_web/rooted.ex:7 names modules renamed in 0.55"))
    end

    test "only code in a template counts: text, comments and strings do not hold the file back" do
      code = ~S'''
      defmodule LegacyAppWeb.Drawer do
        use Phoenix.Component
        alias Brando.Upload

        def store(m, e, c, u), do: Upload.handle_upload(m, e, c, u)

        def drawer(assigns) do
          ~H"""
          <%!-- Upload is not a module here --%>
          <h2>Store current editor state</h2>
          <button aria-label={gettext("Upload media")}>{gettext("Upload")}</button>
          <p>
            {dgettext("drawer",
              "Upload to %{folder}", folder: @folder)}
          </p>
          Upload
          """
        end
      end
      '''

      path = "lib/legacy_app_web/drawer.ex"
      igniter = migrate(@blueprint_054, %{path => code})
      assert igniter.issues == []

      updated = source(igniter, path)
      assert updated =~ "alias Brando.Uploads.Store\n"
      assert updated =~ "do: Store.handle_upload(m, e, c, u)"
      assert updated =~ ~s[{gettext("Upload")}]
      refute Enum.any?(igniter.warnings, &String.contains?(&1, path))
      assert_idempotent(igniter, path)
    end

    test "a name spelled from Elixir. keeps the prefix" do
      code = """
      defmodule LegacyApp.Prefixed do
        alias LegacyApp.Brando

        def store(m, e, c, u), do: Elixir.Brando.Upload.handle_upload(m, e, c, u)
        def own, do: Brando.thing()
      end
      """

      path = "lib/legacy_app/prefixed.ex"
      igniter = migrate(@blueprint_054, %{path => code})
      assert igniter.issues == []

      expected = """
      defmodule LegacyApp.Prefixed do
        alias LegacyApp.Brando

        def store(m, e, c, u), do: Elixir.Brando.Uploads.Store.handle_upload(m, e, c, u)
        def own, do: Brando.thing()
      end
      """

      assert source(igniter, path) == expected
      assert_idempotent(igniter, path)
    end
  end

  describe "image text reads" do
    @hero_blueprint String.replace(@blueprint_054, "attribute :title, :string", """
                    attribute :title, :string

                      assets do
                        asset :hero, :image
                      end
                    """)

    test "lists code that reads an image's texts as strings, using the Blueprints' own asset names" do
      view = """
      defmodule LegacyAppWeb.ProjectHTML do
        use LegacyAppWeb, :html

        def show(assigns) do
          ~H\"\"\"
          <img alt={@project.cover.alt} />
          <p>{@project.hero.title}</p>
          <p>{@project.title}</p>
          <p>{Brando.Images.text(@project.cover, :credits, "no")}</p>
          \"\"\"
        end
      end
      """

      igniter = migrate(@hero_blueprint, %{"lib/legacy_app_web/project_html.ex" => view})

      assert_has_warning(igniter, fn warning ->
        String.contains?(warning, "language → text") and
          String.contains?(warning, "lib/legacy_app_web/project_html.ex:6: <img alt={@project.cover.alt} />") and
          String.contains?(warning, "lib/legacy_app_web/project_html.ex:7: <p>{@project.hero.title}</p>") and
          not String.contains?(warning, ":8:") and not String.contains?(warning, ":9:")
      end)

      # Report only: the file is untouched.
      assert source(igniter, "lib/legacy_app_web/project_html.ex") == view
    end

    test "stays quiet when nothing reads them" do
      igniter = migrate(@blueprint_054)
      refute Enum.any?(igniter.warnings, &String.contains?(&1, "language → text"))
    end
  end

  describe "Villain parsers" do
    @parser_path "lib/legacy_app/villain/parser.ex"

    defp migrate_parser(files) do
      migrate(@blueprint_054, files)
    end

    # Compiles the rewritten parser and returns its diagnostics.
    defp compile_diagnostics(source) do
      {_result, diagnostics} =
        Code.with_diagnostics(fn ->
          modules = Code.compile_string(source, @parser_path)
          for {module, _} <- modules, do: :code.delete(module) and :code.purge(module)
        end)

      diagnostics
    end

    test "a 0.54 parser override gets back what the old __using__ gave it, and compiles cleanly" do
      # smartwatt's parser before the upgrade: a slideshow override rendering
      # ~H with Brando.HTML's <.picture>.
      original = File.read!("test/fixtures/villain_parser/parser_054.ex.txt")

      # As it was, it no longer compiles: ~H and <.picture> came from __using__.
      assert_raise CompileError, fn -> Code.with_diagnostics(fn -> Code.compile_string(original) end) end

      igniter = migrate_parser(%{@parser_path => original})
      upgraded = source(igniter, @parser_path)

      assert upgraded =~ ~r/use Brando.Villain.Parser\n\s*use Phoenix.Component\n\s*import Brando.HTML\n/
      refute upgraded =~ "import Phoenix.HTML"
      assert compile_diagnostics(upgraded) == []

      assert_has_warning(igniter, &String.contains?(&1, "LegacyApp.Villain.Parser.slideshow/2 overrides no block"))

      rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
      assert_unchanged(rerun, @parser_path)
    end

    test "imports and aliases are added only when the parser uses them" do
      plain_path = "lib/legacy_app/villain/plain_parser.ex"

      igniter =
        migrate_parser(%{
          @parser_path => """
          defmodule LegacyApp.Villain.Parser do
            use Brando.Villain.Parser

            def text(%{text: text}, _opts), do: text |> Utils.slugify() |> raw()

            def html(%{text: text}, _opts), do: truncate(text, 20)

            def header(data, opts) when is_map(data), do: Brando.Villain.Parser.header(data, opts)

            def helper(a, b), do: private(a, b)
            defp private(a, b), do: {a, b}
          end
          """,
          plain_path => """
          defmodule LegacyApp.Villain.PlainParser do
            use Brando.Villain.Parser
            use Phoenix.Component
            alias LegacyApp.Utils

            def text(data, _opts) do
              assigns = %{data: data}
              ~H"<p>{Utils.title(@data.text)}</p>"
            end
          end
          """
        })

      upgraded = source(igniter, @parser_path)
      assert upgraded =~ "import Brando.HTML"
      assert upgraded =~ "import Phoenix.HTML"
      assert upgraded =~ "alias Brando.Utils"
      refute upgraded =~ "use Phoenix.Component"
      refute upgraded =~ "alias Brando.Content"
      assert compile_diagnostics(upgraded) == []

      # Already has Phoenix.Component, renders no Brando.HTML component, and
      # its Utils is its own alias.
      assert_unchanged(igniter, plain_path)

      assert_has_warning(igniter, &String.contains?(&1, "LegacyApp.Villain.Parser.helper/2"))
      refute Enum.any?(igniter.warnings, &String.contains?(&1, ".header/2"))
      refute Enum.any?(igniter.warnings, &String.contains?(&1, ".private/2"))
      refute Enum.any?(igniter.warnings, &String.contains?(&1, "PlainParser"))
    end
  end

  test "completes Plural-Forms headers Gettext 1.0 cannot parse" do
    po = fn plural_forms ->
      """
      msgid ""
      msgstr ""
      "Language: no\\n"
      "Plural-Forms: #{plural_forms}\\n"

      msgid "Hello"
      msgstr "Hei"
      """
    end

    paths = %{
      rule_missing: "priv/gettext/backend/no/LC_MESSAGES/default.po",
      semicolon_missing: "priv/gettext/en/LC_MESSAGES/default.po",
      complete: "priv/gettext/sv/LC_MESSAGES/default.po",
      unknown: "priv/gettext/xx/LC_MESSAGES/default.po"
    }

    igniter =
      migrate(@blueprint_054, %{
        paths.rule_missing => po.("nplurals=2;"),
        paths.semicolon_missing => po.("nplurals=2; plural=(n != 1)"),
        paths.complete => po.("nplurals=2; plural=(n != 1);"),
        paths.unknown => po.("nplurals=2;")
      })

    assert source(igniter, paths.rule_missing) == po.("nplurals=2; plural=(n != 1);")
    assert source(igniter, paths.semicolon_missing) == po.("nplurals=2; plural=(n != 1);")
    assert_unchanged(igniter, [paths.complete, paths.unknown])
    assert_has_warning(igniter, &String.contains?(&1, paths.unknown))

    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
    assert_unchanged(rerun, [paths.rule_missing, paths.semicolon_missing])
  end

  test "reports only the 0.55 manual workflow" do
    igniter = migrate(@blueprint_054)

    assert_has_notice(igniter, &String.contains?(&1, "Continue in this order"))
    assert_has_notice(igniter, &String.contains?(&1, "mix brando.gen.migrations"))
    assert_has_notice(igniter, &String.contains?(&1, "Created `florist.config.exs`"))
    assert_has_notice(igniter, &String.contains?(&1, "Archived the recognized legacy task"))
    assert_has_warning(igniter, &String.contains?(&1, "Manual 0.55 decisions remain"))
    assert_has_warning(igniter, &String.contains?(&1, "persist_identifier"))
    assert_has_warning(igniter, &String.contains?(&1, "*_identifiers"))
    assert_has_warning(igniter, &String.contains?(&1, "phoenix_live_view"))
    assert_has_warning(igniter, &String.contains?(&1, "Form.Primitives"))
    assert_has_warning(igniter, &String.contains?(&1, "key_available?/2"))
    assert_has_warning(igniter, &String.contains?(&1, "config_target"))
    assert_has_warning(igniter, &String.contains?(&1, "oban_job_state"))
    assert_has_warning(igniter, &String.contains?(&1, "Database passwords are intentionally not written"))
    refute Enum.any?(igniter.warnings, &String.contains?(&1, "Manual 0.54 decisions"))
    refute Enum.any?(igniter.warnings, &String.contains?(&1, "Brando.Type.Video"))
    refute Enum.any?(igniter.tasks, &match?({"igniter.update_gettext", _}, &1))
  end

  # `{line, module}` for each renamed module `mix brando.doctor` finds in `code`
  defp doctor_findings(code) do
    code
    |> Code.string_to_quoted!()
    |> Brando.Doctor.Checks.Deprecations.scan(%{})
    |> Enum.map(&{&1.line, &1.call})
  end

  defp assert_idempotent(igniter, path) do
    rerun = igniter |> apply_igniter!() |> include_test_files() |> Migrate55.igniter()
    assert_unchanged(rerun, path)
  end

  defp migrate(blueprint, overrides \\ %{}) do
    blueprint |> migrate_files(overrides) |> Migrate55.igniter()
  end

  defp migrate_files(blueprint, overrides) do
    files =
      %{
        @blueprint_path => blueprint,
        @repo_path => @repo,
        @brando_config_path => @brando_config,
        @config_path => @config,
        @package_json_path => @package_json,
        @vite_config_path => @vite_config,
        @deployment_config_path => @deployment_config,
        @fabfile_path => @fabfile,
        @gettext_script_path => legacy_gettext_script(),
        @legacy_task_path => legacy_task("0.54")
      }
      |> Map.merge(overrides)
      |> Enum.reject(fn {_path, contents} -> is_nil(contents) end)
      |> Map.new()

    [app_name: :legacy_app, files: files]
    |> test_project()
    |> include_test_files()
  end

  defp legacy_gettext_script do
    File.read!(Application.app_dir(:brando, "priv/templates/brando.migrate/legacy_sync_gettext/sync_gettext.0.54.sh"))
  end

  defp legacy_task(version) do
    File.read!(Application.app_dir(:brando, [@legacy_templates, "brando.upgrade.#{version}.ex"]))
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
end
