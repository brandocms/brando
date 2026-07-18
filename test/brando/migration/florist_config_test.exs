defmodule Brando.Migration.FloristConfigTest do
  use ExUnit.Case, async: true

  alias Brando.Migration.FloristConfig

  @deployment_config """
  [DEPLOYMENT]
  PROJECT_MODULE = Custom.Site
  PROJECT_NAME = custom_site
  PROD_URL = https://www.example.com/articles
  STAGING_URL = http://staging.example.com
  DB_PASS = never-copy-this-db-secret
  DOCKER_HOST = tcp://docker.example.com:2376
  SSH_USER = deploy
  SSH_PASS = never-copy-this-ssh-secret
  SSH_HOST = app.example.com
  SSH_PORT = 2222
  """

  @fabfile """
  PROJECT_NAME = config.get('DEPLOYMENT', 'PROJECT_NAME')

  GLUE_SETTINGS = {
      'project_name': PROJECT_NAME,
      'project_group': 'site',
      'prod': {
          'project_base': '/srv/production',
          'process_name': '%s_web' % PROJECT_NAME,
          'db_name': "%s_live" % PROJECT_NAME,
          'db_user': 'custom_db_user',
      },
      'staging': {
          'project_base': '/srv/staging',
          'process_name': '%s_stage' % PROJECT_NAME,
          'db_name': "%s_stage" % PROJECT_NAME,
          'db_user': PROJECT_NAME,
      }
  }

  def prod():
      env.flavor = 'production'
      env.mix_env = 'prod'
      env.dockerfile = 'Dockerfile.release'

  def staging():
      env.flavor = 'staging'
      env.mix_env = 'prod'
      env.dockerfile = 'Dockerfile.staging'

  def setup_pgbackup():
      pass

  def setup_rclone():
      pass
  """

  test "converts deterministic Fabric settings without copying credentials" do
    assert {:ok, config, warnings} = FloristConfig.generate(@deployment_config, @fabfile)
    assert {:ok, _ast} = Code.string_to_quoted(config)

    assert config =~ ~s(project_name "custom_site")
    assert config =~ "project_module Custom.Site"
    assert config =~ "target :prod do"
    assert config =~ "target :staging do"
    assert config =~ "set :base_dir, \"/srv/production\""
    assert config =~ "set :process_name, \"${PROJECT_NAME}_web\""
    assert config =~ "set :name, \"${PROJECT_NAME}_live\""
    assert config =~ "set :user, \"custom_db_user\""
    assert config =~ "set :host, \"tcp://docker.example.com:2376\""
    assert config =~ "set :dockerfile, \"Dockerfile.release\""
    assert config =~ "set :domain, \"www.example.com\""
    assert config =~ "set :ssl, :auto"
    assert config =~ "set :domain, \"staging.example.com\""
    assert config =~ "set :ssl, false"
    assert config =~ "set :release_builder, :elixir"
    assert config =~ "set :type, :single"
    assert config =~ "set :type, :nginx"
    assert config =~ "set :blue_port, 8055"
    assert config =~ "set :blue_port, 8060"
    assert config =~ "set :noindex, true"
    assert config =~ "set :pgbackup_enabled, true"
    assert config =~ "FLORIST_DB_PASSWORD_PROD"
    assert config =~ "FLORIST_DB_PASSWORD_STAGING"

    refute config =~ "never-copy-this-db-secret"
    refute config =~ "never-copy-this-ssh-secret"

    assert Enum.any?(warnings, &String.contains?(&1, "Database passwords are intentionally not written"))
    assert Enum.any?(warnings, &String.contains?(&1, "Legacy SSH_PASS was intentionally not copied"))
    assert Enum.any?(warnings, &String.contains?(&1, "persistent media at `<base>/<project>/media`"))
    assert Enum.any?(warnings, &String.contains?(&1, "rclone settings were not copied"))
    assert Enum.any?(warnings, &String.contains?(&1, "PROD_URL contains URL components"))
    assert Enum.any?(warnings, &String.contains?(&1, "prod 8055, staging 8060"))
  end

  test "falls back and warns instead of evaluating Python expressions" do
    fabfile =
      @fabfile
      |> String.replace("'/srv/production'", "dangerous_call()")
      |> String.replace("env.flavor = 'production'", "env.flavor = dangerous_call()")

    assert {:ok, config, warnings} = FloristConfig.generate(@deployment_config, fabfile)

    assert config =~ "set :base_dir, \"/sites/prod\""
    assert config =~ "set :flavor, :prod"
    refute config =~ "dangerous_call"
    assert Enum.any?(warnings, &String.contains?(&1, "Could not convert prod project_base expression"))
    assert Enum.any?(warnings, &String.contains?(&1, "Could not convert prod env.flavor expression"))
  end

  test "warns and falls back when a parsed value cannot form an atom literal" do
    fabfile = String.replace(@fabfile, "env.flavor = 'production'", "env.flavor = 'production-west'")

    assert {:ok, config, warnings} = FloristConfig.generate(@deployment_config, fabfile)

    assert config =~ "set :flavor, :prod"
    assert Enum.any?(warnings, &String.contains?(&1, "Could not render prod env.flavor value"))
  end

  test "requires a safe project module, SSH port, and production target" do
    assert {:error, message} =
             FloristConfig.generate(
               String.replace(@deployment_config, "Custom.Site", "Custom.Site; File.rm_rf!(\"/\")"),
               @fabfile
             )

    assert message =~ "literal Elixir module name"

    assert {:error, message} =
             FloristConfig.generate(
               String.replace(@deployment_config, "SSH_PORT = 2222", "SSH_PORT = invalid"),
               @fabfile
             )

    assert message =~ "SSH_PORT must be an integer"

    assert {:error, message} =
             FloristConfig.generate(@deployment_config, String.replace(@fabfile, "def prod():", "def live():"))

    assert message =~ "does not define the expected prod()"
  end

  test "reports missing required deployment settings" do
    deployment_config = String.replace(@deployment_config, "SSH_HOST = app.example.com\n", "")

    assert {:error, message} = FloristConfig.generate(deployment_config, @fabfile)
    assert message =~ "SSH_HOST"
  end
end
