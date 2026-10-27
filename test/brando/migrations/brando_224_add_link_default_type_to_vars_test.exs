defmodule Brando.Migrations.AddLinkDefaultTypeToVarsTest do
  use Brando.ConnCase

  alias Brando.Content.Var
  alias BrandoIntegration.Repo

  @migration Application.app_dir(
               :brando,
               "priv/templates/brando.upgrade/migrations/brando_224_add_link_default_type_to_vars.exs"
             )

  setup_all do
    [{module, _bytecode}] = Code.compile_file(@migration)

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    %{migration: module}
  end

  # Before the setting, a module var opened on Content by holding an empty
  # link of that type, which every copy of it took along.
  test "a module var that opened on Content keeps its default there", %{migration: migration} do
    module = Brando.Factory.insert(:module)
    var = fn attrs -> Repo.insert!(struct(%Var{type: :link, label: %{"en" => "Link"}, module_id: module.id}, attrs)) end

    content = var.(key: "content", link_type: :identifier)
    url = var.(key: "url", link_type: :url)
    set = var.(key: "set", link_type: :identifier, value: "https://example.com")

    Ecto.Migrator.up(Repo, System.unique_integer([:positive]), migration, log: false, migration_lock: false)

    assert Repo.get!(Var, content.id).link_default_type == :identifier
    assert Repo.get!(Var, url.id).link_default_type == nil
    assert Repo.get!(Var, set.id).link_default_type == nil
  end
end
