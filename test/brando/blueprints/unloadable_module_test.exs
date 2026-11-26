defmodule Brando.Blueprint.UnloadableModuleTest do
  # Sets `:otp_app` and the Logger level, both global
  use Brando.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Brando.Authorization.{Groups, Migration, Scope}
  alias Brando.Content.Identifier
  alias Brando.Factory

  # A site's application whose modules include one that fails to load, as a
  # mailer does when Swoosh's adapter misses an optional dependency.
  @site :unloadable_module_test_site

  @moduletag :tmp_dir
  @moduletag :capture_log

  setup %{tmp_dir: tmp_dir, test: test} do
    # A fresh name per test: a module is warned about once per node
    broken = Module.concat(__MODULE__, "Broken#{System.unique_integer([:positive])}")
    write_unloadable_module(broken, tmp_dir)

    :ok =
      :application.load(
        {:application, @site,
         [
           description: ~c"test site",
           vsn: ~c"0.0.0",
           modules: [Brando.BlueprintTest.Project, broken, Brando.Test.Support],
           registered: [],
           applications: []
         ]}
      )

    on_exit(fn -> :application.unload(@site) end)
    put_test_env(:otp_app, @site)

    previous = Logger.level()
    Logger.configure(level: :warning)
    on_exit(fn -> Logger.configure(level: previous) end)

    %{broken: broken, test: test}
  end

  # A beam on the code path whose `-on_load` function refuses, so loading it
  # fails each time it is tried
  defp write_unloadable_module(module, dir) do
    forms = [
      {:attribute, 1, :module, module},
      {:attribute, 1, :export, []},
      {:attribute, 1, :on_load, {:refuse, 0}},
      {:function, 1, :refuse, 0, [{:clause, 1, [], [], [{:atom, 1, :refused}]}]}
    ]

    {:ok, ^module, binary} = :compile.forms(forms, [:binary])
    File.write!(Path.join(dir, "#{module}.beam"), binary)
    true = :code.add_patha(String.to_charlist(dir))
    on_exit(fn -> :code.del_path(String.to_charlist(dir)) end)
  end

  test "a module that fails to load is not a Blueprint", %{broken: broken} do
    refute Brando.Blueprint.blueprint?(broken)
  end

  test "list_blueprints/0,1 skip it, and warn about it once", %{broken: broken} do
    log =
      capture_log([level: :warning], fn ->
        assert Brando.Blueprint.list_blueprints() == [Brando.BlueprintTest.Project]
        assert Brando.Blueprint.list_blueprints() == [Brando.BlueprintTest.Project]

        assert Brando.Blueprint.list_blueprints(:include_brando) ==
                 [Brando.BlueprintTest.Project, Brando.Pages.Page, Brando.Pages.Fragment]

        assert Brando.Blueprint.app_blueprints(@site) == [Brando.BlueprintTest.Project]
      end)

    assert [_] = Regex.scan(~r/\[warning\].*#{inspect(broken)}/, log)
  end

  test "the datasource scan skips it", %{broken: broken} do
    refute Brando.Datasource.datasource?(broken)
    assert {:ok, []} = Brando.Datasource.Registry.list_modules()
  end

  test "the dashboard lists entries" do
    put_test_env(:tenancy_mode, :none)
    put_test_env(:authorization_mode, :groups)
    owner = Factory.insert(:random_user, role: :superuser)
    user = Factory.insert(:random_user, role: :user)
    {:ok, _} = Migration.run()
    keys = ~w(brando.admin.access brando.pages.read)
    {:ok, group} = Groups.create(Scope.standalone(owner), %{name: "Dashboard access"}, keys)
    {:ok, :ok} = Groups.add_member(Scope.standalone(owner), group.id, user.id)
    page = Factory.insert(:page, title: "Next to a broken mailer", status: :draft)

    Repo.insert!(%Identifier{
      schema: Brando.Pages.Page,
      entry_id: page.id,
      title: page.title,
      status: :draft,
      language: :en,
      updated_at: DateTime.utc_now(:second)
    })

    assert [%{title: "Next to a broken mailer"}] = BrandoAdmin.Dashboard.load(user).recent
  end
end
