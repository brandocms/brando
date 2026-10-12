defmodule Mix.Brando.Igniter.MailerTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Brando.IgniterCase
  alias Mix.Brando.Igniter.Mailer

  # Lett's configuration before its mailer commit, trimmed: no mailer module,
  # Brando's settings in config/brando.exs.
  @brando """
  import Config

  config :brando,
    otp_app: :lett,
    repo_module: Lett.Repo

  config :lett, LettWeb.Guardian, issuer: "lett"
  """

  @dev """
  import Config

  config :lett, hmr: true
  """

  @test """
  import Config

  # Configure your database
  config :lett, Lett.Repo, database: "lett_test"
  """

  @config """
  import Config

  config :lett, ecto_repos: [Lett.Repo]

  import_config "brando.exs"
  import_config "\#{config_env()}.exs"
  """

  defp lett(overrides \\ %{}) do
    files =
      %{
        "config/brando.exs" => @brando,
        "config/dev.exs" => @dev,
        "config/test.exs" => @test,
        "config/config.exs" => @config
      }
      |> Map.merge(overrides)
      |> Enum.reject(&is_nil(elem(&1, 1)))
      |> Map.new()

    igniter = test_project(app_name: :lett, files: files)
    Enum.reduce(Map.keys(files), igniter, &Igniter.include_existing_file(&2, &1))
  end

  defp source(igniter, path), do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  describe "mix brando.migrate55" do
    test "creates the mailer an application lacks, as Lett's mailer commit did" do
      igniter = Mailer.configure_for_upgrade(lett())

      assert source(igniter, "lib/lett/mailer.ex") == """
             defmodule Lett.Mailer do
               use Swoosh.Mailer, otp_app: :lett
             end
             """

      assert source(igniter, "config/dev.exs") =~
               "import Config\n\nconfig :lett, Lett.Mailer, adapter: Swoosh.Adapters.Local\nconfig :lett, hmr: true\n"

      assert source(igniter, "config/test.exs") =~
               "import Config\nconfig :lett, Lett.Mailer, adapter: Swoosh.Adapters.Test\n"

      brando = source(igniter, "config/brando.exs")
      assert brando =~ "mailer: Lett.Mailer"

      assert String.ends_with?(brando, """
             config :lett, LettWeb.Guardian, issuer: "lett"

             # Sender for Brando's own email (password resets, form notifications). Set an
             # address the mail provider sends for; the production adapter goes in
             # runtime.exs.
             config :brando, Brando.Mailer, from: {"Lett", "noreply@example.com"}
             """)

      assert [warning] = igniter.warnings
      assert warning =~ "The task created Lett.Mailer"
      assert warning =~ "in `config/brando.exs`, replacing the\nplaceholder"
      assert warning =~ "config :lett, Lett.Mailer,\n      adapter: Swoosh.Adapters.Mailgun"
      assert igniter.issues == []
    end

    test "without config/brando.exs the sender goes in config.exs, before the environment's import" do
      igniter = Mailer.configure_for_upgrade(lett(%{"config/brando.exs" => nil}))
      config = source(igniter, "config/config.exs")

      [settings, _imports] = String.split(config, "import_config", parts: 2)
      assert settings =~ "config :brando, mailer: Lett.Mailer"
      assert settings =~ ~s(config :brando, Brando.Mailer, from: {"Lett", "noreply@example.com"})
    end

    test "is idempotent" do
      applied = lett() |> Mailer.configure_for_upgrade() |> IgniterCase.apply_and_reload()
      rerun = Mailer.configure_for_upgrade(applied)

      assert_unchanged(rerun)
      assert rerun.warnings == []
    end

    test "keeps a configured sender" do
      sender = @brando <> "\nconfig :brando, Brando.Mailer, from: {\"LETT\", \"noreply@lett.family\"}\n"
      igniter = Mailer.configure_for_upgrade(lett(%{"config/brando.exs" => sender}))

      refute source(igniter, "config/brando.exs") =~ "example.com"
    end

    test "uses the application's Swoosh mailer whatever its name" do
      mailer = "defmodule LettWeb.Mailer do\n  use Swoosh.Mailer, otp_app: :lett\nend\n"
      igniter = Mailer.configure_for_upgrade(lett(%{"lib/lett_web/mailer.ex" => mailer}))

      assert source(igniter, "config/brando.exs") =~ "mailer: LettWeb.Mailer"
      refute Rewrite.has_source?(igniter.rewrite, "lib/lett/mailer.ex")
      assert_unchanged(igniter, ["config/dev.exs", "config/test.exs", "lib/lett_web/mailer.ex"])
      assert igniter.warnings == []
    end

    test "with several Swoosh mailers, names them and changes nothing" do
      igniter =
        lett(%{
          "lib/lett/mailer.ex" => "defmodule Lett.Mailer do\n  use Swoosh.Mailer, otp_app: :lett\nend\n",
          "lib/lett_web/mailer.ex" => "defmodule LettWeb.Mailer do\n  use Swoosh.Mailer, otp_app: :lett\nend\n"
        })
        |> Mailer.configure_for_upgrade()

      assert_unchanged(igniter)
      assert [warning] = igniter.warnings
      assert warning =~ "Lett.Mailer, LettWeb.Mailer"
      assert warning =~ "config :brando, mailer:"
    end

    test "points Brando at an existing mailer without creating anything" do
      mailer = "defmodule Lett.Mailer do\n  use Swoosh.Mailer, otp_app: :lett\nend\n"
      igniter = Mailer.configure_for_upgrade(lett(%{"lib/lett/mailer.ex" => mailer}))

      assert source(igniter, "config/brando.exs") =~ "mailer: Lett.Mailer"
      assert_unchanged(igniter, ["config/dev.exs", "config/test.exs", "lib/lett/mailer.ex"])
      assert igniter.warnings == []
    end
  end

  describe "mix brando.gen.mail" do
    test "creates the mailer without the contact form or dependencies" do
      result = Igniter.compose_task(IgniterCase.phoenix_project(module: "Studio"), "brando.gen.mail", [])

      assert result.issues == []
      assert result.tasks == []
      assert IgniterCase.source(result, "lib/studio/mailer.ex") =~ "use Swoosh.Mailer, otp_app: :studio"
      assert IgniterCase.source(result, "config/config.exs") =~ ~s(from: {"Studio", "noreply@example.com"})
      refute Rewrite.has_source?(result.rewrite, "lib/studio/emails.ex")
      refute Rewrite.has_source?(result.rewrite, "lib/studio/contact/contact_form.ex")
      assert_unchanged(result, "mix.exs")

      assert [notice] = Enum.filter(result.notices, &(&1 =~ "Studio.Mailer is ready"))
      refute notice =~ "Emails.contact"
      assert notice =~ "production\nadapter and credentials in `config/runtime.exs`"
    end

    test "reuses a Swoosh mailer with another name" do
      project =
        IgniterCase.phoenix_project(
          module: "Studio",
          files: %{
            "lib/studio_web/mailer.ex" => "defmodule StudioWeb.Mailer do\n  use Swoosh.Mailer, otp_app: :studio\nend\n"
          }
        )

      result = Igniter.compose_task(project, "brando.gen.mail", [])

      refute Rewrite.has_source?(result.rewrite, "lib/studio/mailer.ex")
      assert IgniterCase.source(result, "config/config.exs") =~ "mailer: StudioWeb.Mailer"
      assert Enum.any?(result.notices, &(&1 =~ "StudioWeb.Mailer is ready"))
    end

    test "--contact also scaffolds the contact form" do
      result = Igniter.compose_task(IgniterCase.phoenix_project(module: "Studio"), "brando.gen.mail", ["--contact"])

      assert IgniterCase.source(result, "lib/studio/emails.ex") =~ "defmodule Studio.Emails"
      assert IgniterCase.source(result, "lib/studio/contact/contact_form.ex") =~ "defmodule Studio.Contact.ContactForm"
      assert Enum.any?(result.notices, &(&1 =~ "Studio.Emails.contact/2"))
    end
  end
end
