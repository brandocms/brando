defmodule Mix.Brando.Igniter.InstallFormatTest.ConfigPlugin do
  @moduledoc false
  # A formatter plugin that reads the project's config, as Igniter evaluates it
  # around formatting. Files it formats end with a comment naming the value.
  def features(_opts), do: [extensions: [".ex", ".exs"]]

  def format(contents, _opts),
    do: String.trim_trailing(contents) <> "\n# #{Application.get_env(:studio, :formatter_marker, "unset")}\n"
end

defmodule Mix.Brando.Igniter.InstallFormatTest do
  # Synchronous: the plugin project configures a marker the plugin reads from
  # the application environment while Igniter formats.
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.InstallFormatTest.ConfigPlugin
  alias Mix.Tasks.Brando.Install

  @migration "priv/repo/migrations/20260101000250_brando_170_add_authorization_groups.exs"

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

  # The installer as it formats each new file through Igniter, and as it formats
  # files without formatter plugins directly.
  defp plans(project, args \\ []) do
    for each? <- [true, false] do
      project |> Igniter.assign(:brando_format_each_file, each?) |> Igniter.compose_task(Install, args)
    end
  end

  defp contents(igniter), do: Map.new(igniter.rewrite.sources, fn {path, source} -> {path, source.content} end)

  defp assert_same_plan(each, direct) do
    assert each.issues == direct.issues
    assert each.warnings == direct.warnings
    assert each.notices == direct.notices
    assert each.tasks == direct.tasks
    assert Map.keys(contents(each)) == Map.keys(contents(direct))
    assert Enum.reject(contents(direct), fn {path, content} -> contents(each)[path] == content end) == []
  end

  test "installs without formatter plugins plan byte-identical files to Igniter's own formatting" do
    for args <- [[], ["--tenancy-mode", "single", "--site-key", "studio"]] do
      [each, direct] = plans(project(), args)
      assert direct.issues == []
      assert_same_plan(each, direct)
    end
  end

  test "a project's formatter settings give the same files and apply to them" do
    files = %{
      ".formatter.exs" => """
      [
        import_deps: [:ecto, :ecto_sql, :phoenix],
        locals_without_parens: [add: 2, add: 3],
        line_length: 50,
        inputs: ["*.{ex,exs}", "{config,lib,priv,test}/**/*.{ex,exs}"]
      ]
      """
    }

    [each, direct] = plans(project(files))
    assert direct.issues == []
    assert_same_plan(each, direct)

    [default, _] = plans(project())
    assert IgniterCase.source(direct, @migration) =~ "add :key, :text"
    refute IgniterCase.source(default, @migration) =~ "add :key, :text"
  end

  # Igniter reads subdirectory formatters from disk, so the plugin's formatter is
  # attached to the in-memory project by hand, as Igniter would read it.
  test "files a formatter plugin applies to are formatted with the project's config, as before" do
    project =
      project(%{
        "config/config.exs" => """
        import Config
        config :studio, formatter_marker: "marked-by-config"
        import_config "dev.exs"
        """
      })

    migrations = %Rewrite.DotFormatter{path: "priv/repo/migrations", plugins: [ConfigPlugin]}
    dot_formatter = %{Rewrite.dot_formatter(project.rewrite) | subs: [migrations]}
    project = Map.update!(project, :rewrite, &Rewrite.dot_formatter(&1, dot_formatter))

    [each, direct] = plans(project)
    assert direct.issues == []
    assert_same_plan(each, direct)
    assert String.ends_with?(IgniterCase.source(direct, @migration), "\n# marked-by-config\n")
    refute IgniterCase.source(direct, "lib/studio/presence.ex") =~ "marked-by-config"
  end
end
