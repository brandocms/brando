defmodule Brando.Doctor.DeployHostsTest do
  use ExUnit.Case, async: true

  alias Brando.Doctor.Checks.DeployHosts
  alias Brando.Doctor.Context
  alias Brando.Doctor.Result

  # What mix brando.install writes without --domain, for the application :my_app
  @prod_template "priv/templates/brando.install/.envrc.prod"
  @staging_template "priv/templates/brando.install/.envrc.staging"

  defp installed(template, host) do
    EEx.eval_file(template, application_name: "my_app", host: host, encryption_secret: true)
  end

  @tag :tmp_dir
  test "the environment files the installer writes without --domain warn, each with its placeholder", %{tmp_dir: root} do
    File.write!(Path.join(root, ".envrc.prod"), installed(@prod_template, "my-app.com"))
    File.write!(Path.join(root, ".envrc.staging"), installed(@staging_template, "staging.my-app.com"))

    assert %Result{status: :warning, summary: summary, fix: fix, items: items} = DeployHosts.evaluate(root, :my_app)
    assert summary =~ ".envrc.prod"
    assert summary =~ ".envrc.staging"
    assert fix =~ "PHX_HOST"
    assert items == [".envrc.prod: PHX_HOST=my-app.com", ".envrc.staging: PHX_HOST=staging.my-app.com"]
  end

  @tag :tmp_dir
  test "the installer's hosts for --domain, or hosts set by hand, are fine", %{tmp_dir: root} do
    File.write!(Path.join(root, ".envrc.prod"), installed(@prod_template, "example.org"))
    File.write!(Path.join(root, ".envrc.staging"), "export PHX_HOST=staging.example.org\n")

    assert %Result{status: :ok} = DeployHosts.evaluate(root, :my_app)
  end

  @tag :tmp_dir
  test "only the placeholder of each file counts, by its last PHX_HOST, not a comment", %{tmp_dir: root} do
    # --staging-domain without --domain: prod keeps the placeholder
    File.write!(Path.join(root, ".envrc.prod"), "# export PHX_HOST=\"my-app.com\"\nexport PHX_HOST='my-app.com'\n")
    # The production placeholder in the staging file is not what the installer writes there
    File.write!(Path.join(root, ".envrc.staging"), "export PHX_HOST=\"my-app.com\"\n")

    assert %Result{status: :warning, items: [".envrc.prod: PHX_HOST=my-app.com"]} = DeployHosts.evaluate(root, :my_app)

    File.write!(Path.join(root, ".envrc.prod"), "export PHX_HOST=\"my-app.com\"\nexport PHX_HOST=\"cms.my-app.no\"\n")
    assert %Result{status: :ok} = DeployHosts.evaluate(root, :my_app)

    # A host the placeholder is only part of
    File.write!(Path.join(root, ".envrc.prod"), "export PHX_HOST=\"my-app.com.au\"\n")
    assert %Result{status: :ok} = DeployHosts.evaluate(root, :my_app)
  end

  @tag :tmp_dir
  test "a file without a PHX_HOST, or with an empty one, warns rather than passing", %{tmp_dir: root} do
    File.write!(Path.join(root, ".envrc.prod"), "# export PHX_HOST=\"my-app.com\"\nexport PHX_SERVER=true\n")
    File.write!(Path.join(root, ".envrc.staging"), "export PHX_HOST=\"\"\n")

    assert %Result{status: :warning, summary: summary, items: items} = DeployHosts.evaluate(root, :my_app)
    assert summary == "no PHX_HOST: .envrc.prod, .envrc.staging"
    assert items == [".envrc.prod: no PHX_HOST", ".envrc.staging: no PHX_HOST"]
  end

  @tag :tmp_dir
  test "the summary lists the files without joining them in English", %{tmp_dir: root} do
    File.write!(Path.join(root, ".envrc.prod"), "export PHX_HOST=\"my-app.com\"\n")
    File.write!(Path.join(root, ".envrc.staging"), "export PHX_HOST=\"staging.my-app.com\"\n")

    assert %Result{summary: "PHX_HOST still the installer's placeholder: .envrc.prod, .envrc.staging"} =
             DeployHosts.evaluate(root, :my_app)

    File.rm!(Path.join(root, ".envrc.staging"))
    File.write!(Path.join(root, ".envrc.prod"), "export PHX_HOST=\"example.org\"\n")
    assert %Result{status: :ok, summary: "PHX_HOST set in .envrc.prod"} = DeployHosts.evaluate(root, :my_app)
  end

  @tag :tmp_dir
  test "without the environment files, there is nothing to check", %{tmp_dir: root} do
    assert %Result{status: :skipped} = DeployHosts.evaluate(root, :my_app)
  end

  @tag :tmp_dir
  test "run/1 reads the context's project directory for the configured application", %{tmp_dir: root} do
    host = Mix.Brando.Install.Hosts.placeholder(Brando.otp_app())
    File.write!(Path.join(root, ".envrc.prod"), "export PHX_HOST=\"#{host}\"\n")

    assert %Result{status: :warning} = DeployHosts.run(Context.new(root: root, locale: "en"))
    assert DeployHosts.needs_source?()
    assert DeployHosts in Brando.Doctor.default_checks()
  end
end
