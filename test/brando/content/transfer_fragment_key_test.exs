defmodule Brando.Content.TransferFragmentKeyTest do
  # A fragment whose stored key doesn't fit the key format: an archive isn't
  # signed, so creating one from it holds the key to the format, as the form
  # does, and the preview says which key and why. Changing the key in the
  # preview, or updating a fragment that has the key already, goes through.
  use Brando.ConnCase, async: false

  alias Brando.Content.Transfer
  alias Brando.{Factory, Repo}
  alias Brando.Pages.Fragment

  setup do
    user = Factory.insert(:random_user)
    fragment = Factory.insert(:fragment, title: "Footer", wrapper: nil, key: "Stored&key", creator: user)

    assert {:ok, exported} = Transfer.export([%{schema: Fragment, id: fragment.id}], user, media: false)
    assert {:ok, archive} = Transfer.read(exported.binary)
    [entry] = archive.bundle["entries"]

    %{user: user, fragment: fragment, archive: archive, key: entry["key"]}
  end

  test "creating one with the stored key is refused, naming the key and why", c do
    assert {:ok, plan} = Transfer.preview(c.archive, %{c.key => %{"mode" => "create"}}, c.user)

    assert Enum.any?(plan.problems, &(&1 =~ "Key: can only hold letters, digits, spaces and _ - . / ( )"))
    refute Enum.any?(plan.problems, &(&1 =~ "%{"))
    assert {:error, _} = Transfer.apply(plan, c.user)
  end

  test "creating one goes through with a key changed in the preview", c do
    targets = %{c.key => %{"mode" => "create", "attributes" => %{"key" => "site-footer"}}}

    assert {:ok, plan} = Transfer.preview(c.archive, targets, c.user)
    assert plan.problems == []
    assert {:ok, receipt} = Transfer.apply(plan, c.user)
    assert Repo.get!(Fragment, receipt.after[c.key]["id"]).key == "site-footer"
  end

  test "updating a fragment that has the stored key already goes through", c do
    targets = %{c.key => %{"mode" => "update", "id" => c.fragment.id}}

    assert {:ok, plan} = Transfer.preview(c.archive, targets, c.user)
    assert plan.problems == []
    assert {:ok, _receipt} = Transfer.apply(plan, c.user)
    assert Repo.get!(Fragment, c.fragment.id).key == "Stored&key"
  end
end
