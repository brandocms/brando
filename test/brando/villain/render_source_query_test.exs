defmodule Brando.Villain.RenderSourceQueryTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Content.Container
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.Villain.RenderSourceQuery

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
