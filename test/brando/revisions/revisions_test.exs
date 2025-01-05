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
    s1a = %Page{
      title: "My title!",
      alternate_entries: [],
      alternates: [],
      children: [],
      entry_blocks: [],
      fragments: [],
      parent: nil,
      meta_image: nil,
      vars: []
    }

    p1 = Brando.repo().insert!(s1a)
    {:ok, r1} = Revisions.create_revision(p1, user)

    p2 =
      p1
      |> Ecto.Changeset.change(title: "New title")
      |> Brando.repo().update!()

    {:ok, r2} = Revisions.create_revision(p2, user)

    refute r1 == r2
    assert r1.revision == 0
    assert r2.revision == 1
    refute r1.encoded_entry == r2.encoded_entry

    assert :erlang.binary_to_term(r1.encoded_entry) == p1
    assert :erlang.binary_to_term(r2.encoded_entry) == p2
  end

  test "get_last_revision", %{user: user} do
    s1a = %Page{title: "My title!"}
    s1b = %{s1a | title: "A new title!"}

    p1 = Brando.repo().insert!(s1a)
    p2 = Brando.repo().insert!(s1b)

    {:ok, _} = Revisions.create_revision(p1, user)
    {:ok, r2} = Revisions.create_revision(p2, user)

    {:ok, {last_revision, {_, _}}} = Revisions.get_last_revision(Page, p2.id)
    assert last_revision.revision == r2.revision
  end

  test "set", %{user: user} do
    {:ok, p1} = Pages.create_page(Factory.params_for(:page, vars: []), user)
    {:ok, p2} = Pages.update_page(p1.id, %{title: "Title no. 2"}, user)
    {:ok, p3} = Pages.update_page(p2.id, %{title: "Title no. 3"}, user)

    assert p3.title == "Title no. 3"

    Revisions.set_entry_to_revision(Page, p1.id, 1, user)
    {:ok, p4} = Pages.get_page(%{matches: %{id: p3.id}})
    assert p4.title == "Title no. 2"
  end
end
