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

    # One database role per target, as FLORIST_DB_PASSWORD_<TARGET> has one password per target.
    prod_env = IgniterCase.source(igniter, ".envrc.prod")
    staging_env = IgniterCase.source(igniter, ".envrc.staging")
    assert prod_env =~ ~s(DATABASE_URL="postgres://studio:__BRANDO_DATABASE_PASSWORD__@localhost/studio_prod")

    assert staging_env =~
             ~s(DATABASE_URL="postgres://studio_staging:__BRANDO_DATABASE_PASSWORD__@localhost/studio_staging")

    assert prod_env =~ ~s(SECRET_KEY_BASE="__BRANDO_SECRET_KEY_BASE__")
    assert prod_env =~ ~s(export RELEASE_NODE="${RELEASE_NODE:-studio_prod@127.0.0.1}")
    assert staging_env =~ ~s(export RELEASE_NODE="${RELEASE_NODE:-studio_staging@127.0.0.1}")
    refute prod_env =~ ~r/^export PORT=/m
    assert {"brando.install.secrets", [".envrc.prod", ".envrc.staging"]} in igniter.tasks

    release_env = IgniterCase.source(igniter, "rel/env.sh.eex")
    assert release_env =~ ~s(. "$RELEASE_ROOT/.envrc.runtime")
    assert release_env =~ "export RELEASE_NODE=${RELEASE_NODE:-<%= @release.name %>@127.0.0.1}"

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

  test "without --domain, --yes writes no check_origin, uses placeholder hosts and asks nothing" do
    igniter = install(project(), ["--yes"])

    assert igniter.issues == []
    refute_received {:mix_shell, :prompt, _}
    Igniter.Test.assert_unchanged(igniter, "config/prod.exs")
    assert host(igniter, ".envrc.prod") == "studio.com"
    assert host(igniter, ".envrc.staging") == "staging.studio.com"
    assert Enum.any?(igniter.notices, &(&1 =~ "placeholder studio.com"))
    assert Enum.any?(igniter.notices, &(&1 =~ "check_origin was not written"))
  end

  test "--origin or --staging-domain without --domain writes no check_origin" do
    igniter = install(project(), ["--yes", "--origin", "//cms.example.net", "--staging-domain", "qa.example.net"])

    assert igniter.issues == []
    Igniter.Test.assert_unchanged(igniter, "config/prod.exs")
    assert host(igniter, ".envrc.staging") == "qa.example.net"
    assert Enum.any?(igniter.notices, &(&1 =~ "check_origin was not written"))
  end

  test "a rerun with only --origin, on an installed application, says why nothing was written" do
    envrc = "export PHX_HOST=\"realsite.no\"\n"

    igniter =
      project(%{".envrc.prod" => envrc, ".envrc.staging" => envrc, ".gitignore" => "/.envrc.*\n"})
      |> install(["--yes", "--origin", "//cms.example.net"])

    Igniter.Test.assert_unchanged(igniter, "config/prod.exs")
    assert Enum.any?(igniter.notices, &(&1 =~ "take effect only with a domain"))
  end

  test "environment files an earlier run left with secret markers get their secrets filled in" do
    marked = "export PHX_HOST=\"realsite.no\"\nexport SECRET_KEY_BASE=\"__BRANDO_SECRET_KEY_BASE__\"\n"
    filled = "export PHX_HOST=\"realsite.no\"\nexport SECRET_KEY_BASE=\"done\"\n"

    igniter =
      project(%{".envrc.prod" => marked, ".envrc.staging" => filled, ".gitignore" => "/.envrc.*\n"})
      |> install(["--yes"])

    assert {"brando.install.secrets", [".envrc.prod"]} in igniter.tasks
  end

  test "prod connects as Florist's default database user, staging as its own" do
    igniter = install(project(), ["--yes", "--domain", "example.com"])

    assert IgniterCase.source(igniter, ".envrc.prod") =~
             "postgres://studio:__BRANDO_DATABASE_PASSWORD__@localhost/studio_prod"

    assert IgniterCase.source(igniter, ".envrc.staging") =~
             "postgres://studio_staging:__BRANDO_DATABASE_PASSWORD__@localhost/studio_staging"
  end

  test "a rerun on an installed application without check_origin writes none" do
    envrc = "export PHX_HOST=\"realsite.no\"\n"

    igniter =
      project(%{".envrc.prod" => envrc, ".envrc.staging" => envrc, ".gitignore" => "/.envrc.*\n"})
      |> install(["--yes"])

    assert igniter.issues == []
    Igniter.Test.assert_unchanged(igniter, ["config/prod.exs", ".envrc.prod", ".envrc.staging", ".gitignore"])
    refute Enum.any?(igniter.notices, &(&1 =~ "No --domain was given"))
  end

  test "a rerun with --domain keeps the hosts the existing environment files serve" do
    igniter =
      project(%{
        ".envrc.prod" => "export PHX_HOST=\"realsite.no\"\n",
        ".envrc.staging" => "export BRANDO_URL_HOST='staging.studio.com'\n"
      })
      |> install(["--yes", "--domain", "example.com"])

    assert check_origin(igniter) == ["//example.com", "//*.example.com", "//staging.example.com", "//realsite.no"]
  end

  test "a check_origin in a config file imported with a literal path is kept" do
    igniter =
      project(%{
        "config/config.exs" => """
        import Config
        import_config "endpoint.exs"
        import_config "\#{config_env()}.exs"
        """,
        "config/endpoint.exs" => """
        import Config
        import_config "endpoint/origins.exs"
        """,
        "config/endpoint/origins.exs" => """
        import Config
        config :studio, StudioWeb.Endpoint, check_origin: ["//live.example.com"]
        """
      })
      |> install(["--yes", "--domain", "example.com"])

    assert igniter.issues == []
    Igniter.Test.assert_unchanged(igniter, "config/prod.exs")
    assert Enum.any?(igniter.notices, &(&1 =~ "already configures check_origin"))
  end

  test "an existing release script is kept, with a notice when it does not source the environment file" do
    script = "#!/bin/sh\nexport RELEASE_DISTRIBUTION=name\n"
    igniter = project(%{"rel/env.sh.eex" => script}) |> install(["--yes", "--domain", "example.com"])

    Igniter.Test.assert_unchanged(igniter, "rel/env.sh.eex")
    assert Enum.any?(igniter.notices, &(&1 =~ "rel/env.sh.eex does not source .envrc.runtime"))

    sourcing = script <> ". \"$RELEASE_ROOT/.envrc.runtime\"\n"
    igniter = project(%{"rel/env.sh.eex" => sourcing}) |> install(["--yes", "--domain", "example.com"])

    Igniter.Test.assert_unchanged(igniter, "rel/env.sh.eex")
    refute Enum.any?(igniter.notices, &(&1 =~ "does not source"))
    refute Enum.any?(igniter.notices, &(&1 =~ "short node names"))

    short = "#!/bin/sh\n. \"$RELEASE_ROOT/.envrc.runtime\"\n"
    igniter = project(%{"rel/env.sh.eex" => short}) |> install(["--yes", "--domain", "example.com"])
    assert Enum.any?(igniter.notices, &(&1 =~ "keeps the default short node names"))
  end

  test "a leading space or an unreadable negation does not count as ignoring the environment files" do
    for gitignore <- [" .envrc*\n", ".envrc*\n!.envrc.[ps]rod\n"] do
      igniter = project(%{".gitignore" => gitignore}) |> install(["--yes", "--domain", "example.com"])
      assert IgniterCase.source(igniter, ".gitignore") =~ "\n/.envrc.prod\n", inspect(gitignore)
    end
  end

  test "an environment file un-ignored by a later negation gets an explicit ignore line" do
    igniter =
      project(%{".gitignore" => "/_build/\n.envrc*\n!/.envrc.prod\n"})
      |> install(["--yes", "--domain", "example.com"])

    assert IgniterCase.source(igniter, ".gitignore") ==
             "/_build/\n.envrc*\n!/.envrc.prod\n\n# Runtime environments with secrets, uploaded by Florist\n/.envrc.prod\n"
  end

  test "invalid hosts and origins are blocking issues" do
    for {args, message} <- [
          {["--domain", "https://example.com"], "--domain must be a host name"},
          {["--domain", "example.com/path"], "--domain must be a host name"},
          {["--domain", "localhost"], "--domain must be a host name"},
          {["--domain", "127.0.0.1"], "--domain must be a host name"},
          {["--origin", "//*.com"], "--origin must be an origin"},
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

  test "--interactive keeps the placeholder, and writes no check_origin, on an empty domain answer" do
    for _ <- 1..3, do: send(self(), {:mix_shell_input, :prompt, ""})

    igniter = install(project(), ["--interactive", "--tenancy-mode", "none"])

    assert igniter.issues == []
    Igniter.Test.assert_unchanged(igniter, "config/prod.exs")
    assert host(igniter, ".envrc.prod") == "studio.com"
    assert host(igniter, ".envrc.staging") == "staging.studio.com"
  end

  test "--interactive asks no extra origins when check_origin exists and only environment files are missing" do
    send(self(), {:mix_shell_input, :prompt, "example.org"})
    send(self(), {:mix_shell_input, :prompt, ""})

    igniter =
      project(%{
        "config/prod.exs" => "import Config\nconfig :studio, StudioWeb.Endpoint, check_origin: [\"//example.org\"]\n"
      })
      |> install(["--interactive", "--tenancy-mode", "none"])

    assert igniter.issues == []
    assert_received {:mix_shell, :prompt, ["+ Production domain [studio.com]"]}
    assert_received {:mix_shell, :prompt, ["+ Staging host [staging.example.org]"]}
    refute_received {:mix_shell, :prompt, _}
    Igniter.Test.assert_unchanged(igniter, "config/prod.exs")
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
      assert {:error, _} = Hosts.domain("127.0.0.1")
      assert {:error, _} = Hosts.domain("example.123")
      assert Hosts.domain("123.example.com") == {:ok, "123.example.com"}
    end

    test "accepts the origin forms Phoenix's check_origin parses" do
      for origin <- [
            "//example.com",
            "//*.example.com",
            "//*.preview.client.no",
            "https://*.a.b.c:8443",
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
            "//example.com:0",
            "//*.com",
            "//*.localhost"
          ] do
        assert {:error, _} = Hosts.origin(origin)
      end
    end

    test "placeholders are valid host names built from the application name" do
      assert Hosts.placeholder(:photo_blog) == "photo-blog.com"
      assert {:ok, _} = Hosts.domain(Hosts.placeholder(:photo_blog))
    end
  end

  describe "brando.install.secrets" do
    @describetag :tmp_dir

    test "fills in the planned markers once, readable by the owner only", %{tmp_dir: dir} do
      File.cd!(dir, fn ->
        File.write!(
          ".envrc.prod",
          ~s(export DATABASE_URL="postgres://a:__BRANDO_DATABASE_PASSWORD__@h/d"\nexport SECRET_KEY_BASE="__BRANDO_SECRET_KEY_BASE__"\n)
        )

        Mix.Tasks.Brando.Install.Secrets.run([".envrc.prod"])
        filled = File.read!(".envrc.prod")

        refute filled =~ "__BRANDO_"
        assert filled =~ ~r"postgres://a:[A-Za-z0-9_-]{32}@h/d"
        assert [_, key] = Regex.run(~r/SECRET_KEY_BASE="([^"]+)"/, filled)
        assert byte_size(key) == 64
        assert File.stat!(".envrc.prod").mode |> Bitwise.band(0o777) == 0o600

        Mix.Tasks.Brando.Install.Secrets.run([".envrc.prod"])
        assert File.read!(".envrc.prod") == filled
      end)
    end

    test "refuses other files" do
      assert_raise Mix.Error, ~r/Unknown environment file: config\/prod.exs/, fn ->
        Mix.Tasks.Brando.Install.Secrets.run(["config/prod.exs"])
      end
    end
  end
end
