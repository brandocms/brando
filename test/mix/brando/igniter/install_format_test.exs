defmodule Mix.Brando.Igniter.InstallFormatTest.ConfigPlugin do
  @moduledoc false
  # A formatter plugin that reads the project's config, as Igniter evaluates it
  # around formatting. Files it formats end with a comment naming the value.
  def features(_opts), do: [extensions: [".ex", ".exs"]]

  def format(contents, _opts),
    do: String.trim_trailing(contents) <> "\n# #{Application.get_env(:studio, :formatter_marker, "unset")}\n"
end

defmodule Mix.Brando.Igniter.InstallFormatTest do
  # Synchronous: Igniter's formatting puts the projects' config into the
  # application environment, and the plugin project relies on that.
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.InstallFormatTest.ConfigPlugin
  alias Mix.Tasks.Brando.Install

  @migration "priv/repo/migrations/20260101000250_brando_170_add_authorization_groups.exs"

  # phx.new's formatters: HTMLFormatter at the root, and migrations with a
  # formatter of their own.
  @phoenix_formatter """
  [
    import_deps: [:ecto, :ecto_sql, :phoenix],
    subdirectories: ["priv/*/migrations"],
    plugins: [Phoenix.LiveView.HTMLFormatter],
    inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
  ]
  """
  @migrations_formatter """
  [
    import_deps: [:ecto_sql],
    inputs: ["*.exs"]
  ]
  """

  defp project(files \\ %{}) do
    IgniterCase.phoenix_project(
      files:
        Map.merge(
          %{
            "config/config.exs" => """
            import Config
            config :studio, StudioWeb.Endpoint, secret_key_base: "existing-secret"
            import_config "dev.exs"
            """,
            "config/dev.exs" => "import Config\n",
            "lib/studio_web/gettext.ex" => "defmodule StudioWeb.Gettext do\n use Gettext.Backend, otp_app: :studio\nend\n"
          },
          files
        )
    )
  end

  defp phoenix_project do
    project(%{".formatter.exs" => @phoenix_formatter, "priv/repo/migrations/.formatter.exs" => @migrations_formatter})
    |> with_sub_formatter("priv/repo/migrations", @migrations_formatter)
  end

  # Igniter finds subdirectory formatters on disk, so one is read the way
  # Rewrite reads it and attached to the in-memory project by hand.
  defp with_sub_formatter(igniter, dir, contents) do
    {:ok, sub} =
      [Rewrite.Source.from_string(contents, path: ".formatter.exs")]
      |> Rewrite.from_sources!()
      |> Rewrite.DotFormatter.read()

    root = Rewrite.dot_formatter(igniter.rewrite)
    Map.update!(igniter, :rewrite, &Rewrite.dot_formatter(&1, %{root | subs: [%{sub | path: dir}]}))
  end

  # The installer as it formats each new file through Igniter, and as it formats
  # files directly when their formatter cannot read the project's config.
  defp plans(project, args \\ []) do
    for each? <- [true, false] do
      project |> Igniter.assign(:brando_format_each_file, each?) |> Igniter.compose_task(Install, args)
    end
  end

  defp contents(igniter),
    do: Map.new(igniter.rewrite.sources, fn {path, source} -> {path, {source.content, Rewrite.Source.issues(source)}} end)

  defp assert_same_plan(each, direct) do
    assert each.issues == direct.issues
    assert each.warnings == direct.warnings
    assert each.notices == direct.notices
    assert each.tasks == direct.tasks
    assert Map.keys(contents(each)) == Map.keys(contents(direct))
    assert Enum.reject(contents(direct), fn {path, planned} -> contents(each)[path] == planned end) == []
  end

  test "installs into a phx.new project plan byte-identical files to Igniter's own formatting" do
    for args <- [[], ["--tenancy-mode", "single", "--site-key", "studio"]] do
      [each, direct] = plans(phoenix_project(), args)
      assert direct.issues == []
      assert_same_plan(each, direct)
    end
  end

  test "the formatters of a phx.new project apply to the planned files" do
    [phoenix, _] = plans(phoenix_project())
    [plain, _] = plans(project())

    # HTMLFormatter rewraps the dashboard's ~H template at the root...
    dashboard = "lib/studio_admin/dashboard_live.ex"
    assert IgniterCase.source(phoenix, dashboard) =~ "~H"
    assert IgniterCase.source(phoenix, dashboard) != IgniterCase.source(plain, dashboard)

    # ...and the migrations' formatter imports Ecto's calls without parentheses.
    assert IgniterCase.source(phoenix, @migration) =~ "add :key, :text"
    refute IgniterCase.source(plain, @migration) =~ "add :key, :text"
  end

  test "a project's formatter settings give the same files" do
    files = %{
      ".formatter.exs" => """
      [
        import_deps: [:ecto, :ecto_sql, :phoenix],
        locals_without_parens: [create: 1],
        line_length: 50,
        inputs: ["*.{ex,exs}", "{config,lib,priv,test}/**/*.{ex,exs}"]
      ]
      """
    }

    [each, direct] = plans(project(files))
    assert direct.issues == []
    assert_same_plan(each, direct)
    assert IgniterCase.source(direct, @migration) =~ "create index("
  end

  test "files a plugin that reads the project's config applies to are formatted with that config, as before" do
    project =
      project(%{
        "config/config.exs" => """
        import Config
        config :studio, formatter_marker: "marked-by-config"
        import_config "dev.exs"
        """
      })
      |> with_sub_formatter("priv/repo/migrations", "[plugins: [#{inspect(ConfigPlugin)}], inputs: [\"*.exs\"]]")

    [each, direct] = plans(project)
    assert direct.issues == []
    assert_same_plan(each, direct)
    assert String.ends_with?(IgniterCase.source(direct, @migration), "\n# marked-by-config\n")
    refute IgniterCase.source(direct, "lib/studio/presence.ex") =~ "marked-by-config"
  end

  # Files.create relies on this; an Igniter upgrade that changes it must fail here.
  test "Igniter.format/2 with no paths reads the config and formatter files and formats nothing" do
    unformatted = "defmodule Studio.Loose do\n def a,   do:   1\nend\n"

    igniter =
      IgniterCase.phoenix_project(
        files: %{"lib/studio/loose.ex" => unformatted, "config/config.exs" => "import Config\n"}
      )

    igniter = %{igniter | rewrite: Rewrite.drop(igniter.rewrite, ["config/config.exs", ".formatter.exs"])}
    prepared = Igniter.format(igniter, [])

    assert IgniterCase.source(prepared, "lib/studio/loose.ex") == unformatted
    assert Rewrite.has_source?(prepared.rewrite, "config/config.exs")
    assert Rewrite.has_source?(prepared.rewrite, ".formatter.exs")
    refute IgniterCase.source(Igniter.format(prepared, nil), "lib/studio/loose.ex") == unformatted
  end
end
