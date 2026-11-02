defmodule BrandoAdmin.Sites.PublishingDeployTargetsTest do
  # Someone who may deploy one site reaches only that site's destination: the
  # deploy runs with the server's one SSH identity and one set of S3 credentials,
  # and the other site's rights are never consulted.
  use Brando.LiveCase

  alias Brando.Authorization.Groups
  alias Brando.Authorization.Migration
  alias Brando.Authorization.Scope
  alias Brando.Factory
  alias Brando.Sites.DeployConfig
  alias Brando.Tenant.Access
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  @rsync_parent "deploy@static.example.test:/srv/sites"
  @bucket "s3://static-bucket/sites"

  setup do
    root = Path.join(System.tmp_dir!(), "brando-deploy-targets-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    allow_per_site_targets()
    Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Cache.clear()
    end)

    {site_a, environment_a} = create_site("alpha")
    {site_b, _environment_b} = create_site("beta")
    %{site_a: site_a, site_b: site_b, environment_a: environment_a}
  end

  defp allow_per_site_targets do
    put_test_env(DeployConfig,
      rsync_targets: ["#{@rsync_parent}/{site_key}"],
      s3_targets: ["#{@bucket}/{site_key}"]
    )
  end

  defp create_site(name) do
    key = "#{name}-#{System.unique_integer([:positive])}"

    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :rsync, target: "#{@rsync_parent}/#{key}"}
      })

    {:ok, environment} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})
    {Registry.get_site(site.id), environment}
  end

  defp deploy_holder(context) do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Migration.run()
    user = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    scope = Scope.site(context.current_user, context.site_a, context.environment_a)

    {:ok, group} =
      Groups.create(scope, %{name: "Alpha publishers #{System.unique_integer([:positive])}"}, [
        "brando.admin.access",
        "brando.publishing.read",
        "brando.publishing.deploy"
      ])

    {:ok, :ok} = Groups.add_member(scope, group.id, user.id)
    user
  end

  defp legacy_site_admin(context) do
    put_test_env(:authorization_mode, :legacy)
    user = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    {:ok, _} = Access.grant(user, context.site_a, :admin)
    user
  end

  defp save(view, strategy, target) do
    render_submit(form(view, "#static-deploy-config"), %{"deploy" => %{"strategy" => strategy, "target" => target}})
  end

  defp saved_target(site), do: Registry.get_site(site.id).deploy_config.target

  for {mode, person} <- [groups: :deploy_holder, legacy: :legacy_site_admin] do
    describe "#{mode} mode" do
      test "a person on one site cannot save another site's destination", context do
        own = saved_target(context.site_a)
        user = unquote(person)(context)
        {:ok, view, _html} = live(log_in_user(build_conn(), user), "/admin/config/publishing")

        save(view, "rsync", "#{@rsync_parent}/#{context.site_b.key}")
        assert saved_target(context.site_a) == own

        save(view, "s3", "#{@bucket}/#{context.site_b.key}")
        assert saved_target(context.site_a) == own

        # The whole bucket holds both sites
        save(view, "s3", "s3://static-bucket")
        assert saved_target(context.site_a) == own

        save(view, "s3", "#{@bucket}/#{context.site_a.key}")
        assert saved_target(context.site_a) == "#{@bucket}/#{context.site_a.key}"

        save(view, "rsync", own)
        assert saved_target(context.site_a) == own
      end

      test "with several sites and no list, no destination can be saved", context do
        own = saved_target(context.site_a)
        put_test_env(DeployConfig, [])
        user = unquote(person)(context)
        {:ok, view, _html} = live(log_in_user(build_conn(), user), "/admin/config/publishing")

        save(view, "rsync", "#{@rsync_parent}/#{context.site_b.key}")
        assert saved_target(context.site_a) == own

        save(view, "s3", "#{@bucket}/#{context.site_b.key}")
        assert saved_target(context.site_a) == own
      end
    end
  end
end
