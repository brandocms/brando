defmodule Brando.SoftDelete.RepoTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory

  test "randomize slug on delete, normalize on restore" do
    p1 = Factory.insert(:page)
    assert p1.slug == "title"
    {:ok, p2} = Brando.repo().soft_delete(p1)
    refute p2.slug == "title"
    {:ok, p3} = Brando.repo().restore(p2)
    assert p3.slug == "title"
  end

  test "avoid collision when restoring" do
    user = Factory.insert(:random_user)

    {:ok, p1} = Brando.Pages.create_page(Factory.params_for(:page), user)
    {:ok, p2} = Brando.Pages.create_page(Factory.params_for(:page), user)

    assert p1.slug == "title"
    refute p1.slug == p2.slug

    {:ok, p3} = Brando.repo().soft_delete(p1)
    refute p3.slug == "title"

    {:ok, p4} = Brando.Pages.create_page(Factory.params_for(:page), user)
    assert p4.slug == "title"

    {:ok, p5} = Brando.repo().restore(p1)
    refute p5.slug == "title"
  end
end
