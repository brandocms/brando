Code.require_file("../../../support/mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Brando.GenerateTest do
  use ExUnit.Case

  import MixHelper

  @app_name "photo_blog"
  @tmp_path tmp_path()
  @project_path Path.join(@tmp_path, @app_name)
  @root_path Path.expand(".")

  setup_all do
    templates_path =
      Path.join([@project_path, "deps", "brando", "lib", "brando_admin", "templates"])

    root_path = File.cwd!()

    # Clean up
    File.rm_rf(@project_path)

    # Create path for app
    File.mkdir_p(Path.join(@project_path, "brando"))

    # Create path for templates
    File.mkdir_p(templates_path)

    File.cp_r!(Path.join([root_path, "lib", "brando_admin", "templates"]), templates_path)

    # Move into the project directory to run the generator
    File.cd!(@project_path)

    on_exit(fn ->
      File.cd!(@root_path)
    end)
  end

  # `Mix.shell()` is global, and these tests only work under
  # `Mix.Shell.Process` — the seeded `{:mix_shell_input, :prompt, _}` messages
  # go nowhere otherwise, and `Mix.Shell.IO` answers from a closed CI stdin with
  # `:eof`. Owning it here rather than inheriting whatever the run happens to
  # have installed: the load-time `Mix.shell/1` call in `mix_helper.exs` is one
  # assignment for the whole suite, and CI has caught it not holding.
  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.Process) end)
    :ok
  end

  test "brando.install" do
    Mix.Tasks.Brando.Install.run([])
    refute_received {:mix_shell, :prompt, _message}
    assert_received {:mix_shell, :info, ["\nBrando finished copying."]}
    assert File.exists?("lib/brando_web/villain")
    assert_file("lib/brando_web/villain/parser.ex")
    assert File.dir?("priv/repo/tenant_migrations")
    assert_file("priv/repo/migrations/20260101000243_brando_163_add_shared_content_library.exs")
    assert_file("priv/repo/migrations/20260101000244_brando_164_add_ssg_builds.exs")
    assert_file("priv/repo/tenant_migrations/20260816002300_add_shared_content_library.exs")

    assert_file("config/runtime.exs", fn file ->
      assert file =~ ~s<url: System.get_env("BRANDO_DB_URL")>
    end)

    assert_file("config/brando.exs", fn file ->
      assert file =~ "tenancy_mode: :none"
      refute file =~ "site_key:"
    end)

    assert_file("lib/brando_web/components/layouts.ex", fn file ->
      assert file =~ "embed_templates \"layouts/*\""
      assert file =~ "embed_templates \"partials/*\""
    end)

    assert_file("lib/brando_web/router.ex", fn file ->
      assert file =~ "plug Brando.Plug.Tenant"
    end)

    assert_file("mix.exs", fn file ->
      assert file =~ "defmodule Brando.MixProject do"
    end)

    assert_file("assets/frontend/package.json", fn file ->
      assert file =~ "brando Frontend"
    end)

    assert_file("lib/brando_admin/live/dashboard_live.ex", fn file ->
      assert file =~ "use BrandoAdmin.LiveView.Listing, schema: nil"
    end)

    assert_file("priv/repo/migrations/20260101000250_brando_170_add_authorization_groups.exs", fn file ->
      assert file =~ "authorization_groups"
      assert file =~ "authorization_legacy_mappings"
    end)

    # Every versioned migration comes from the maintained upgrade source, and
    # runs in numeric order even when older versions were added after newer ones.
    installed = Path.wildcard("priv/repo/migrations/*_brando_*.exs") |> Enum.sort()
    templates = Path.wildcard(Path.join(@root_path, "priv/templates/brando.upgrade/migrations/*.exs"))
    assert length(installed) == length(templates)

    sequences =
      Enum.map(installed, fn path ->
        [_, filename, sequence] = Regex.run(~r/\d+_(brando_(\d+)_.+\.exs)$/, path)
        template = Path.join(@root_path, "priv/templates/brando.upgrade/migrations/#{filename}")
        assert File.read!(path) == EEx.eval_file(template)
        String.to_integer(sequence)
      end)

    assert sequences == Enum.sort(sequences)
    assert length(sequences) == length(Enum.uniq(sequences))

    refute File.exists?("assets/css/app.css")
  end

  test "accepts --interactive through the Mix task entry point" do
    send(self(), {:mix_shell_input, :prompt, "single"})
    send(self(), {:mix_shell_input, :prompt, "guided-site"})
    Mix.Tasks.Brando.Install.run(["--interactive"])

    assert_received {:mix_shell, :prompt, [prompt]}
    assert prompt =~ "Choose tenancy mode"

    assert_file("config/brando.exs", fn file ->
      assert file =~ "tenancy_mode: :single"
      assert file =~ ~s(site_key: "guided-site")
    end)
  end

  test "parses valid installer tenancy options" do
    assert Mix.Tasks.Brando.Install.parse_tenancy_options!([]) == %{
             mode: :none,
             site_key: nil
           }

    assert Mix.Tasks.Brando.Install.parse_tenancy_options!(
             tenancy_mode: "single",
             site_key: "photo-blog"
           ) == %{mode: :single, site_key: "photo-blog"}

    assert Mix.Tasks.Brando.Install.parse_tenancy_options!(tenancy_mode: "multi") == %{
             mode: :multi,
             site_key: nil
           }
  end

  test "renders single-site tenancy configuration" do
    config =
      "templates/brando.install/config/brando.exs"
      |> Mix.Tasks.Brando.Install.render()
      |> EEx.eval_string(
        application_name: "photo_blog",
        application_module: "PhotoBlog",
        tenancy_mode: :single,
        site_key: "photo-blog"
      )

    assert config =~ "tenancy_mode: :single"
    assert config =~ ~s(site_key: "photo-blog")
  end

  test "guides interactive single-site setup and supplies the project key default" do
    send(self(), {:mix_shell_input, :prompt, "2"})
    send(self(), {:mix_shell_input, :prompt, ""})

    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!([tenancy_prompt: true], "photo-blog") == %{
             mode: :single,
             site_key: "photo-blog"
           }

    assert_received {:mix_shell, :prompt, [mode_prompt]}
    assert mode_prompt =~ "Choose tenancy mode"
    assert mode_prompt =~ "2. single"
    assert_received {:mix_shell, :prompt, [site_prompt]}
    assert site_prompt =~ "Site key [photo-blog]"
  end

  test "supports non-interactive installs without tenancy flags" do
    assert Mix.Tasks.Brando.Install.resolve_tenancy_options!(
             [tenancy_prompt: false],
             "photo-blog"
           ) == %{mode: :none, site_key: nil}

    refute_received {:mix_shell, :prompt, _message}
  end

  test "rejects incomplete or contradictory installer tenancy options" do
    assert_raise Mix.Error, ~r/--site-key is required/, fn ->
      Mix.Tasks.Brando.Install.parse_tenancy_options!(tenancy_mode: "single")
    end

    assert_raise Mix.Error, ~r/--site-key can only be used/, fn ->
      Mix.Tasks.Brando.Install.parse_tenancy_options!(site_key: "photo-blog")
    end

    assert_raise Mix.Error, ~r/Invalid --tenancy-mode/, fn ->
      Mix.Tasks.Brando.Install.parse_tenancy_options!(tenancy_mode: "global")
    end
  end
end
