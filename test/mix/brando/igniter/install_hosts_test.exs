defmodule Mix.Brando.Igniter.InstallHostsTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase
  alias Mix.Brando.Install.Hosts
  alias Mix.Tasks.Brando.Install

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp project(files \\ %{}) do
    IgniterCase.phoenix_project(
      files:
        Map.merge(
          %{
            "config/config.exs" => "import Config\nimport_config \"\#{config_env()}.exs\"\n",
            "config/dev.exs" => "import Config\nconfig :studio, StudioWeb.Endpoint, check_origin: false\n",
            "config/prod.exs" => """
            import Config
            config :studio, StudioWeb.Endpoint, cache_static_manifest: "priv/static/cache_manifest.json"
            """
          },
          files
        )
    )
  end

  defp install(igniter, args), do: Igniter.compose_task(igniter, Install, args)

  defp check_origin(igniter) do
    quoted = igniter.rewrite |> Rewrite.source!("config/prod.exs") |> Rewrite.Source.get(:quoted)

    {_, origins} =
      Macro.prewalk(quoted, nil, fn
        {{:__block__, _, [:check_origin]}, value} = node, nil -> {node, value}
        node, found -> {node, found}
      end)

    origins |> Code.eval_quoted() |> elem(0)
  end

  defp host(igniter, path) do
    [_, host] = Regex.run(~r/^export PHX_HOST="([^"]*)"$/m, IgniterCase.source(igniter, path))
    host
  end

  test "--domain, --staging-domain and repeated --origin fill check_origin and the environment files" do
    igniter =
      install(project(), [
        "--yes",
        "--domain",
        "Example.com",
        "--staging-domain",
        "preview.example.net",
        "--origin",
        "//*.agency.example",
        "--origin",
        "https://admin.example.org:8443"
      ])

    assert igniter.issues == []
    refute_received {:mix_shell, :prompt, _}

    assert check_origin(igniter) == [
             "//example.com",
             "//*.example.com",
             "//preview.example.net",
             "//*.agency.example",
             "https://admin.example.org:8443"
           ]

    prod = IgniterCase.source(igniter, "config/prod.exs")
    assert prod =~ ~s(cache_static_manifest: "priv/static/cache_manifest.json")

    assert host(igniter, ".envrc.prod") == "example.com"
    assert host(igniter, ".envrc.staging") == "preview.example.net"

    assert IgniterCase.source(igniter, ".envrc.prod") =~
             ~r{DATABASE_URL="postgres://studio:[A-Za-z0-9_-]+@localhost/studio_prod"}

    assert IgniterCase.source(igniter, ".envrc.staging") =~ "@localhost/studio_staging\""
    refute IgniterCase.source(igniter, ".envrc.prod") =~ ~r/^export PORT=/m

    gitignore = IgniterCase.source(igniter, ".gitignore")
    assert gitignore =~ "/_build/"
    assert gitignore =~ "\n/.envrc.prod\n/.envrc.staging\n"

    refute Enum.any?(igniter.notices, &(&1 =~ "placeholder"))
  end

  test "the staging host defaults to staging.<domain>" do
    igniter = install(project(), ["--domain", "example.com"])

    assert check_origin(igniter) == ["//example.com", "//*.example.com", "//staging.example.com"]
    assert host(igniter, ".envrc.staging") == "staging.example.com"
  end

  test "without --domain, --yes uses the placeholder hosts and asks nothing" do
    igniter = install(project(), ["--yes"])

    assert igniter.issues == []
    refute_received {:mix_shell, :prompt, _}
    assert check_origin(igniter) == ["//studio.com", "//*.studio.com", "//staging.studio.com"]
    assert host(igniter, ".envrc.prod") == "studio.com"
    assert host(igniter, ".envrc.staging") == "staging.studio.com"
    assert Enum.any?(igniter.notices, &(&1 =~ "placeholder studio.com"))
  end

  test "invalid hosts and origins are blocking issues" do
    for {args, message} <- [
          {["--domain", "https://example.com"], "--domain must be a host name"},
          {["--domain", "example.com/path"], "--domain must be a host name"},
          {["--domain", "localhost"], "--domain must be a host name"},
          {["--staging-domain", "*.example.com"], "--staging-domain must be a host name"},
          {["--origin", "example.com"], "--origin must be an origin"},
          {["--origin", "ftp://example.com"], "--origin must be an origin"},
          {["--origin", "//example.com/path"], "--origin must be an origin"},
          {["--origin", "//example.com:99999"], "--origin must be an origin"}
        ] do
      igniter = install(project(), ["--yes" | args])
      assert Enum.any?(igniter.issues, &(&1 =~ message)), "#{inspect(args)}: #{inspect(igniter.issues)}"
      Igniter.Test.assert_unchanged(igniter)
    end
  end

  test "--interactive asks for the domain, staging host and origins, and asks again after an invalid answer" do
    send(self(), {:mix_shell_input, :prompt, "https://example.org/"})
    send(self(), {:mix_shell_input, :prompt, "example.org"})
    send(self(), {:mix_shell_input, :prompt, ""})
    send(self(), {:mix_shell_input, :prompt, "//*.agency.example, https://cms.example.net"})

    igniter = install(project(), ["--interactive", "--tenancy-mode", "none"])

    assert igniter.issues == []
    assert_received {:mix_shell, :prompt, ["+ Production domain [studio.com]"]}
    assert_received {:mix_shell, :error, [error]}
    assert error =~ "must be a host name"
    assert_received {:mix_shell, :prompt, ["+ Production domain [studio.com]"]}
    assert_received {:mix_shell, :prompt, ["+ Staging host [staging.example.org]"]}
    assert_received {:mix_shell, :prompt, ["+ Extra trusted origins, comma-separated []"]}
    refute_received {:mix_shell, :prompt, _}

    assert check_origin(igniter) == [
             "//example.org",
             "//*.example.org",
             "//staging.example.org",
             "//*.agency.example",
             "https://cms.example.net"
           ]

    assert host(igniter, ".envrc.staging") == "staging.example.org"
  end

  test "--interactive skips the host questions that options answer" do
    send(self(), {:mix_shell_input, :prompt, "example.org"})

    igniter =
      install(project(), [
        "--interactive",
        "--tenancy-mode",
        "none",
        "--staging-domain",
        "qa.example.org",
        "--origin",
        "//cms.example.net"
      ])

    assert_received {:mix_shell, :prompt, ["+ Production domain [studio.com]"]}
    refute_received {:mix_shell, :prompt, _}
    assert check_origin(igniter) == ["//example.org", "//*.example.org", "//qa.example.org", "//cms.example.net"]
  end

  test "an application's own check_origin, environment files and ignore rules are kept" do
    envrc = "export PHX_HOST=\"live.example.com\"\n"

    igniter =
      project(%{
        "config/runtime.exs" => """
        import Config
        if config_env() == :prod do
          config :studio, StudioWeb.Endpoint, check_origin: ["//live.example.com"]
        end
        """,
        ".envrc.prod" => envrc,
        ".gitignore" => "/_build/\n.envrc*\n"
      })
      |> install(["--yes", "--domain", "example.com"])

    assert igniter.issues == []
    Igniter.Test.assert_unchanged(igniter, ["config/prod.exs", "config/runtime.exs", ".envrc.prod", ".gitignore"])
    assert host(igniter, ".envrc.staging") == "staging.example.com"
    assert Enum.any?(igniter.notices, &(&1 =~ "already configures check_origin"))
    assert Enum.any?(igniter.notices, &(&1 =~ "Existing environment files were left unchanged: .envrc.prod"))
  end

  test "a rerun of an applied install changes nothing and asks nothing" do
    applied = project() |> install(["--yes", "--domain", "example.com"]) |> Igniter.Test.apply_igniter!()
    reloaded = Enum.reduce(Map.keys(applied.assigns.test_files), applied, &Igniter.include_existing_file(&2, &1))

    rerun = install(reloaded, ["--interactive", "--tenancy-mode", "none", "--domain", "other.example"])

    assert rerun.issues == []
    refute_received {:mix_shell, :prompt, _}
    Igniter.Test.assert_unchanged(rerun)
    assert host(rerun, ".envrc.prod") == "example.com"
    assert Enum.any?(rerun.notices, &(&1 =~ "already configures check_origin"))

    plain = install(reloaded, ["--interactive", "--tenancy-mode", "none"])
    refute_received {:mix_shell, :prompt, _}
    Igniter.Test.assert_unchanged(plain)
  end

  describe "validation" do
    test "accepts host names and normalises case" do
      assert Hosts.domain(" Example.COM ") == {:ok, "example.com"}
      assert Hosts.domain("a-b.c.example.co.uk") == {:ok, "a-b.c.example.co.uk"}
      assert {:error, _} = Hosts.domain("-bad.example.com")
      assert {:error, _} = Hosts.domain("example.com:443")
      assert {:error, _} = Hosts.domain("exa mple.com")
    end

    test "accepts the origin forms Phoenix's check_origin parses" do
      for origin <- [
            "//example.com",
            "//*.example.com",
            "https://example.com",
            "http://localhost:4000",
            "//host.example:8080"
          ] do
        assert Hosts.origin(origin) == {:ok, origin}
      end

      assert Hosts.origin("HTTPS://Example.com") == {:ok, "https://example.com"}

      for origin <- [
            "example.com",
            "//",
            "//*.",
            "wss://example.com",
            "//ex*ample.com",
            "https://example.com/",
            "//example.com:0"
          ] do
        assert {:error, _} = Hosts.origin(origin)
      end
    end

    test "placeholders are valid host names built from the application name" do
      assert Hosts.placeholder(:photo_blog) == "photo-blog.com"
      assert {:ok, _} = Hosts.domain(Hosts.placeholder(:photo_blog))
    end
  end
end
