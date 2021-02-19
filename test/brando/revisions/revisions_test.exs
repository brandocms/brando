defmodule Brando.Revisions.RevisionsTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Revisions
  alias Brando.Pages
  alias Brando.Pages.Page

  setup do
    user = Factory.insert(:random_user)
    {:ok, %{user: user}}
  end

  test "create_revision", %{user: user} do
    s1a = %Page{id: 1, title: "My title!"}
    s1b = %{s1a | title: "A new title!"}
    {:ok, r1} = Revisions.create_revision(s1a, user)
    {:ok, r2} = Revisions.create_revision(s1b, user)

    refute r1 == r2
    assert r1.revision == 0
    assert r2.revision == 1
    refute r1.encoded_entry == r2.encoded_entry

    assert :erlang.binary_to_term(r1.encoded_entry) == s1a
    assert :erlang.binary_to_term(r2.encoded_entry) == s1b
  end

  test "get_last_revision", %{user: user} do
    s1a = %Page{id: 1, title: "My title!"}
    s1b = %{s1a | title: "A new title!"}
    {:ok, _} = Revisions.create_revision(s1a, user)
    {:ok, r2} = Revisions.create_revision(s1b, user)

    {:ok, {last_revision, {_, _}}} = Revisions.get_last_revision(%Page{id: 1})
    assert last_revision.revision == r2.revision
  end

  test "set", %{user: user} do
    {:ok, p1} = Pages.create_page(Factory.params_for(:page), user)
    {:ok, p2} = Pages.update_page(p1.id, %{title: "Title no. 2"}, user)
    {:ok, p3} = Pages.update_page(p2.id, %{title: "Title no. 3"}, user)

    assert p3.title == "Title no. 3"

    Revisions.set_revision(p3, 1)
    {:ok, p4} = Pages.get_page(%{matches: %{id: p3.id}})
    assert p4.title == "Title no. 2"

    Revisions.set_last_revision(p4)
    {:ok, p4} = Pages.get_page(%{matches: %{id: p3.id}})
    assert p4.title == "Title no. 3"
  end
end
