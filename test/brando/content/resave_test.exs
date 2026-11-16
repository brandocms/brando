defmodule Brando.Content.ResaveTest do
  use Brando.ConnCase

  import ExUnit.CaptureIO

  alias Brando.Content.Resave

  setup do
    user = Brando.Factory.insert(:random_user)
    fragment = Brando.Factory.insert(:fragment, creator: user, key: "resaved", title: "Resaved")

    {1, _} =
      Brando.Repo.update_all(Ecto.Query.from(f in Brando.Pages.Fragment, where: f.id == ^fragment.id),
        set: [rendered_blocks: "stale"]
      )

    %{fragment: fragment}
  end

  # As `bin/my_app rpc` runs it: the application is running, and the report
  # goes to standard output
  test "on a running node it re-saves, reports, and reloads the node's caches", %{fragment: fragment} do
    Cachex.put(:query, {:resave_test, :cached}, :cached)

    output = capture_io(fn -> assert {:ok, 1} = Resave.run(blueprint: "Brando.Pages.Fragment") end)

    assert Brando.Repo.get!(Brando.Pages.Fragment, fragment.id).rendered_blocks != "stale"
    assert output =~ "==> Resaving fragment entries"
    assert output =~ "done!"
    assert output =~ ~r/Resaved \d+ entr(y|ies)\./
    assert output =~ "Emptied and reloaded this node's caches"
    assert {:ok, nil} = Cachex.get(:query, {:resave_test, :cached})
  end

  test "reload_caches: false leaves the caches and says how to empty them" do
    Cachex.put(:query, {:resave_test, :kept}, :cached)

    output = capture_io(fn -> Resave.run(blueprint: Brando.Pages.Fragment, reload_caches: false) end)

    assert output =~ "Servers that were already running keep serving what they cached before."
    assert {:ok, :cached} = Cachex.get(:query, {:resave_test, :kept})
  end

  test "lists every Blueprint and asks before re-saving them all" do
    parent = self()

    output =
      capture_io(fn ->
        decline = fn plan ->
          send(parent, {:plan, plan})
          false
        end

        assert {:ok, :declined} = Resave.run(confirm: decline, reload_caches: false)
      end)

    assert output =~ "Blueprint schemas that will be resaved"
    assert output =~ "Nothing was done."
    assert_received {:plan, %{blueprints: [Brando.Pages.Fragment | _] = blueprints, environments: [nil]}}
    assert Brando.Pages.Page in blueprints
  end

  test "an option that names nothing is an error, before anything is done" do
    assert {:error, "--site and --environment need tenancy, which is off"} = Resave.run(site: "acme")
    assert {:error, "Brando.Nothing is not a Blueprint"} = Resave.run(blueprint: "Brando.Nothing")
  end
end
