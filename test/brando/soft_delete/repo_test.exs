defmodule Brando.SoftDelete.RepoTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory

  test "randomize uri on delete, normalize on restore" do
    p1 = Factory.insert(:page, uri: "title")
    assert p1.uri == "title"

    {:ok, p2} = Brando.repo().soft_delete(p1)
    refute p2.uri == "title"

    {:ok, p3} = Brando.repo().restore(p2)
    assert p3.uri == "title"
  end

  test "avoid collision when restoring" do
    user = Factory.insert(:random_user)

    {:ok, p1} = Brando.Pages.create_page(Factory.params_for(:page, uri: "title"), user)
    {:ok, p2} = Brando.Pages.create_page(Factory.params_for(:page, uri: "title"), user)

    assert p1.uri == "title"
    refute p1.uri == p2.uri

    {:ok, p3} = Brando.repo().soft_delete(p1)
    refute p3.uri == "title"

    {:ok, p4} = Brando.Pages.create_page(Factory.params_for(:page, uri: "title"), user)
    assert p4.uri == "title"

    {:ok, p5} = Brando.repo().restore(p1)
    refute p5.uri == "title"
  end
end
