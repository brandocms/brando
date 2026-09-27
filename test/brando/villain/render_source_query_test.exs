defmodule Brando.Villain.RenderSourceQueryTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Container
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.Villain.RenderSourceQuery
  alias Brando.Villain.RenderScope

  test "cold module projections share the library query" do
    first = Factory.insert(:module)
    second = Factory.insert(:module)
    opts = %{cache: true}
    owner = self()
    handler = {__MODULE__, make_ref()}
    event = Brando.repo().config()[:telemetry_prefix] ++ [:query]
    Brando.Cache.Query.evict_schema(Brando.Content.Module)

    :telemetry.attach(handler, event, fn _, _, _, _ -> send(owner, :query) end, nil)

    on_exit(fn ->
      :telemetry.detach(handler)
      Brando.Cache.Query.evict_schema(Brando.Content.Module)
    end)

    assert RenderSourceQuery.get_module(first.id, opts).id == first.id
    assert_received :query
    refute_received :query
    assert RenderSourceQuery.get_module(second.id, opts).id == second.id
    refute_received :query
  end

  test "a render batch reuses its source snapshot and the next render sees fresh data" do
    first = Factory.insert(:module)

    second =
      RenderScope.run(fn ->
        assert {:ok, modules} = RenderSourceQuery.list_modules()
        assert Enum.map(modules, & &1.id) == [first.id]
        second = Factory.insert(:module)
        assert RenderSourceQuery.list_modules() == {:ok, modules}
        second
      end)

    assert {:ok, modules} = RenderScope.run(fn -> RenderSourceQuery.list_modules() end)
    assert Enum.sort(Enum.map(modules, & &1.id)) == Enum.sort([first.id, second.id])
  end

  test "individual module cache follows both entry and schema eviction" do
    module = Factory.insert(:module, vars: [Factory.build(:var_text, sequence: 2), Factory.build(:var_text, sequence: 1)])
    opts = %{cache: {:ttl, :infinite}, preload: [vars: {Brando.Content.Var, [asc: :sequence]}]}
    on_exit(fn -> Brando.Cache.Query.evict_schema(Brando.Content.Module) end)

    assert %{vars: [%{sequence: 1}, %{sequence: 2}]} = RenderSourceQuery.get_module(module.id, opts)
    updated = module |> Ecto.Changeset.change(code: "Updated") |> Repo.update!()
    assert RenderSourceQuery.get_module(module.id, opts).code == module.code
    Brando.Cache.Query.evict(updated)
    assert RenderSourceQuery.get_module(module.id, opts).code == "Updated"

    updated |> Ecto.Changeset.change(deleted_at: DateTime.truncate(DateTime.utc_now(), :second)) |> Repo.update!()
    Brando.Cache.Query.evict_schema(Brando.Content.Module)
    assert RenderSourceQuery.get_module(module.id, opts) == nil
    assert RenderSourceQuery.get_module(nil, opts) == nil
  end

  test "lists only non-deleted modules and applies rendering preloads" do
    module = Factory.insert(:module, vars: [Factory.build(:var_text)])
    _deleted = Factory.insert(:module, deleted_at: DateTime.utc_now())

    assert {:ok, modules} = RenderSourceQuery.list_modules(%{preload: [:vars]})
    assert Enum.map(modules, & &1.id) == [module.id]
    assert [%Brando.Content.Var{}] = hd(modules).vars
  end

  test "lists containers with their configured palettes" do
    palette = Factory.insert(:palette)

    container =
      %Container{
        type: :liquid,
        name: "container",
        namespace: "site",
        code: "{{ content }}",
        palette_id: palette.id
      }
      |> Repo.insert!()

    assert {:ok, containers} = RenderSourceQuery.list_containers(%{preload: [:palette]})
    assert Enum.map(containers, & &1.id) == [container.id]
    assert hd(containers).palette.id == palette.id
  end

  test "lists only non-deleted palettes" do
    palette = Factory.insert(:palette)
    _deleted = Factory.insert(:palette, key: "deleted", deleted_at: DateTime.utc_now())

    assert {:ok, palettes} = RenderSourceQuery.list_palettes()
    assert Enum.map(palettes, & &1.id) == [palette.id]
  end
end
