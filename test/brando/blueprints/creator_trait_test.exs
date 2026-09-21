defmodule Brando.Trait.CreatorTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Pages

  defp page_params(attrs \\ %{}) do
    Map.merge(
      %{
        title: "Title",
        uri: "creator-trait-#{System.unique_integer([:positive])}",
        language: "en",
        template: "default.html",
        status: :draft
      },
      attrs
    )
  end

  test "insert stamps creator and last editor to the same instant" do
    user = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)

    assert page.creator_id == user.id
    assert page.updated_by_id == user.id
    assert %DateTime{} = page.edited_at
  end

  test "a user save moves updated_by and edited_at, and keeps the creator" do
    creator = Factory.insert(:random_user)
    editor = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), creator)

    edited_at = DateTime.add(page.edited_at, -3600, :second)
    Brando.Repo.update_all(Pages.Page, set: [edited_at: edited_at])

    {:ok, updated} = Pages.update_page(page.id, %{title: "Changed"}, editor)

    assert updated.creator_id == creator.id
    assert updated.updated_by_id == editor.id
    assert DateTime.compare(updated.edited_at, edited_at) == :gt
  end

  test "a :system save leaves the editor alone" do
    user = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)

    {:ok, updated} = Pages.update_page(page.id, %{title: "System"}, :system)

    assert updated.title == "System"
    assert updated.updated_by_id == user.id
    assert updated.edited_at == page.edited_at
  end

  test "re-rendering blocks bumps updated_at but not edited_at or updated_by" do
    user = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)

    stale = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -3600, :second)
    stale_naive = DateTime.to_naive(stale)
    Brando.Repo.update_all(Pages.Page, set: [updated_at: stale_naive, edited_at: stale])

    {:ok, rendered} = Brando.Content.Blocks.render_entry(Pages.Page, page.id)

    assert NaiveDateTime.compare(rendered.updated_at, stale_naive) == :gt
    assert DateTime.compare(rendered.edited_at, stale) == :eq
    assert rendered.updated_by_id == user.id
  end

  test "a changeset with only rendered_* changes is not an edit" do
    user = Factory.insert(:random_user)
    other = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)

    changeset =
      Brando.Trait.Creator.changeset_mutator(
        Pages.Page,
        %{},
        Ecto.Changeset.change(page, %{rendered_blocks: "<p>x</p>"}),
        other,
        []
      )

    refute Map.has_key?(changeset.changes, :updated_by_id)
    refute Map.has_key?(changeset.changes, :edited_at)
  end

  test "a no-op save leaves everything untouched" do
    user = Factory.insert(:random_user)
    other = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)

    {:ok, same} = Pages.update_page(page.id, %{title: page.title}, other)

    assert same.updated_by_id == user.id
    assert same.edited_at == page.edited_at
  end
end
