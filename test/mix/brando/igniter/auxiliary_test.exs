defmodule Mix.Brando.Igniter.AuxiliaryTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase

  @tasks ~w(mail sitemap authorization release)

  test "auxiliary generators compose, use configured namespaces and preserve reruns" do
    project = IgniterCase.phoenix_project(app: :shop, module: "Acme.Shop", web: "Acme.Web")
    result = Enum.reduce(@tasks, project, &Igniter.compose_task(&2, "brando.gen.#{&1}", []))
    assert result.issues == []
    assert result.tasks == [{"deps.get", []}]
    assert result.rms == []
    assert IgniterCase.source(result, "lib/acme/shop/mailer.ex") =~ "otp_app: :shop"
    assert IgniterCase.source(result, "lib/acme/web/sitemap.ex") =~ "defmodule Acme.Web.Sitemap"
    assert IgniterCase.source(result, "lib/acme/shop/authorization.ex") =~ "Brando.Images.Image"
    assert IgniterCase.source(result, "mix.exs") =~ "steps: [:assemble, :tar]"
    refute_received {:mix_shell, :prompt, _}

    applied = IgniterCase.apply_and_reload(result)
    rerun = Enum.reduce(@tasks, applied, &Igniter.compose_task(&2, "brando.gen.#{&1}", []))
    assert rerun.issues == []
    Igniter.Test.assert_unchanged(rerun)
  end

  test "mail reuses an existing mailer and preserves selected dependency and adapter" do
    path = "lib/studio/mailer.ex"

    project =
      IgniterCase.phoenix_project(
        files: %{
          path => "defmodule Studio.Mailer do\n def custom, do: true\nend",
          "config/dev.exs" => "import Config\nconfig :studio, Studio.Mailer, adapter: MyAdapter\n"
        }
      )

    project =
      Igniter.update_file(project, "mix.exs", fn source ->
        Rewrite.Source.update(
          source,
          :content,
          String.replace(
            Rewrite.Source.get(source, :content),
            "[{:brando,",
            "[{:swoosh, path: \"../swoosh\"}, {:req, path: \"../req\"}, {:brando,"
          )
        )
      end)

    project = IgniterCase.apply_and_reload(project)
    result = Igniter.compose_task(project, "brando.gen.mail", [])
    assert result.issues == []
    Igniter.Test.assert_unchanged(result, path)
    Igniter.Test.assert_unchanged(result, "config/dev.exs")
    Igniter.Test.assert_unchanged(result, "mix.exs")
    email = IgniterCase.source(result, "lib/studio/emails.ex")
    assert email =~ "Keyword.fetch!(options, :to)"
    assert email =~ "Ecto.Changeset.apply_action!"
    assert email =~ "Email.text_body"
    refute email =~ "domain.tld"
  end

  test "customized output blocks plans even with yes" do
    for {task, path, module} <- [
          {"mail", "lib/studio/emails.ex", "Studio.Emails"},
          {"sitemap", "lib/studio_web/sitemap.ex", "StudioWeb.Sitemap"},
          {"authorization", "lib/studio/authorization.ex", "Studio.Authorization"},
          {"release", "lib/studio/release_tasks.ex", "Studio.ReleaseTasks"}
        ] do
      result =
        IgniterCase.phoenix_project(files: %{path => "defmodule #{module} do\n def custom, do: true\nend"})
        |> Igniter.compose_task("brando.gen.#{task}", ["--yes"])

      assert Enum.any?(result.issues, &String.contains?(&1, "different content"))
      Igniter.Test.assert_unchanged(result, path)
    end
  end

  test "release keeps existing runtime, deployment files and release definitions" do
    files = %{
      ".envrc" => "export SECRET_KEY_BASE=keep-me\n",
      "Dockerfile" => "FROM my-custom-image\n",
      "fabfile.py" => "# my deployment\n",
      "config/runtime.exs" => "import Config\nconfig :studio, secret: System.fetch_env!(\"SECRET\")\n"
    }

    project = IgniterCase.phoenix_project(files: files)

    project =
      Igniter.Project.MixProject.update(project, :project, [:releases], fn _ ->
        {:ok, {:code, [studio: [steps: [:assemble]], worker: [include_erts: false]]}}
      end)

    project = IgniterCase.apply_and_reload(project)
    result = Igniter.compose_task(project, "brando.gen.release", [])
    assert result.issues == []
    Enum.each(["mix.exs" | Map.keys(files)], &Igniter.Test.assert_unchanged(result, &1))
    assert result.tasks == []
    assert result.rms == []
  end

  test "consumer auxiliary templates take precedence" do
    template = "priv/templates/brando.gen.sitemap/lib/application_name_web/sitemap.ex"

    result =
      IgniterCase.phoenix_project(
        files: %{template => "defmodule <%= web_module %>.Sitemap do\n def custom, do: true\nend"}
      )
      |> Igniter.compose_task("brando.gen.sitemap", [])

    assert result.issues == []
    assert IgniterCase.source(result, "lib/studio_web/sitemap.ex") =~ "def custom"
  end

  test "Fabric retirement gives an actionable replacement without writing files" do
    assert_raise Mix.Error, ~r/brando.gen.release.*guides\/deployment.md/, fn ->
      Mix.Tasks.Brando.Install.Fabfile.run([])
    end
  end
end
