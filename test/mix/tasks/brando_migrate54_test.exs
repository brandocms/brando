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

    list :all, {__MODULE__, :list_all, [status: :published]}
    selection :featured, &__MODULE__.list_featured/3, &__MODULE__.get_featured/1

    listings do
      listing do
        listing_query %{order: "asc title"}
        filters [[label: "Title", filter: "title"], [label: "Status", key: "status"]]
        filter label: "Direct legacy", filter: "direct"
        filter label: "Already keyed", filter: "obsolete", key: "authoritative"
        actions [[label: "Duplicate", event: "duplicate"]]
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
      json_ld_field :name, :string, & &1.title
    end

    meta_schema do
      meta_field "title", & &1.title
    end

    def list(left, right), do: {left, right}
    def list_all(_module, _language, _vars), do: []
    def list_featured(_module, _language, _vars), do: []
    def get_featured(identifiers), do: identifiers
    def villains, do: Brando.Villain.list_villains()
    def villains_fun, do: &Brando.Villain.list_villains/0
  end
  """

  @legacy_live_preview """
  defmodule LegacyAppWeb.LivePreview do
    use Brando.LivePreview

    preview_target LegacyApp.Projects.Project do
      layout_module LegacyAppWeb.Layouts
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

  test "rewrites the complete legacy Blueprint surface without changing unrelated calls" do
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
    assert blueprint =~ "query(%{preload: [:creator]})"
    assert blueprint =~ "input(:slug, :slug, source: :title)"
    assert blueprint =~ "input(:related_entries, :entries, sources: [{__MODULE__, %{}}])"
    assert blueprint =~ "field(:name, :string, & &1.title)"
    assert blueprint =~ "field(\"title\", & &1.title)"

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
    refute live_preview =~ "view_module"
    refute live_preview =~ "view_template"
    assert live_preview =~ "layout({LegacyAppWeb.Layouts, :app})"
    assert live_preview =~ "template({LegacyAppWeb.ProjectHTML, \"show.html\"})"
    assert live_preview =~ "layout({LegacyAppWeb.ArticleLayouts, :app})"
    assert live_preview =~ "{LegacyAppWeb.ArticleHTML,"
    assert live_preview =~ "(fn entry -> entry.template end).(entry)"
  end

  test "is idempotent across Blueprint, LivePreview, and copied-file changes" do
    first_pass = migrate(@legacy_blueprint, @legacy_live_preview)

    second_pass =
      first_pass
      |> apply_igniter!()
      |> Migrate54.igniter()

    assert_unchanged(second_pass)
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

    igniter = [app_name: :legacy_app, files: files] |> test_project() |> Migrate54.igniter()

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
    assert_has_warning(igniter, &String.contains?(&1, "phoenix_live_view"))
    assert_has_warning(igniter, &String.contains?(&1, "config_target"))
    assert_has_warning(igniter, &String.contains?(&1, "oban_job_state"))
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
        @fonts_path => @fonts
      }
      |> Map.merge(overrides)
      |> maybe_put(@live_preview_path, live_preview)

    [app_name: :legacy_app, files: files]
    |> test_project()
    |> Migrate54.igniter()
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
