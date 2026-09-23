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

  test "insert records the creator and leaves the editor empty" do
    user = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)

    assert page.creator_id == user.id
    assert page.updated_by_id == nil
    assert page.edited_at == nil
  end

  test "a user save stamps updated_by and edited_at, and keeps the creator" do
    creator = Factory.insert(:random_user)
    editor = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), creator)

    {:ok, updated} = Pages.update_page(page.id, %{title: "Changed"}, editor)

    assert updated.creator_id == creator.id
    assert updated.updated_by_id == editor.id
    assert %DateTime{} = updated.edited_at
  end

  test "a later user save moves edited_at forward" do
    user = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)
    {:ok, edited} = Pages.update_page(page.id, %{title: "First"}, user)

    earlier = DateTime.add(edited.edited_at, -3600, :second)
    Brando.Repo.update_all(Pages.Page, set: [edited_at: earlier])

    {:ok, updated} = Pages.update_page(page.id, %{title: "Second"}, user)

    assert DateTime.compare(updated.edited_at, earlier) == :gt
  end

  test "a :system save leaves the editor alone" do
    user = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)
    {:ok, edited} = Pages.update_page(page.id, %{title: "Edited"}, user)

    {:ok, updated} = Pages.update_page(page.id, %{title: "System"}, :system)

    assert updated.title == "System"
    assert updated.updated_by_id == user.id
    assert updated.edited_at == edited.edited_at
  end

  test "a :system save does not turn a created entry into an edited one" do
    user = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)

    {:ok, updated} = Pages.update_page(page.id, %{title: "System"}, :system)

    assert updated.updated_by_id == nil
    assert updated.edited_at == nil
  end

  test "re-rendering blocks bumps updated_at but not edited_at or updated_by" do
    user = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)
    {:ok, _} = Pages.update_page(page.id, %{title: "Edited"}, user)

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
    {:ok, edited} = Pages.update_page(page.id, %{title: "Edited"}, user)

    {:ok, same} = Pages.update_page(page.id, %{title: edited.title}, other)

    assert same.updated_by_id == user.id
    assert same.edited_at == edited.edited_at
  end

  test "transferring a user's content moves both ownership and edits" do
    leaving = Factory.insert(:random_user)
    recipient = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), leaving)
    {:ok, _} = Pages.update_page(page.id, %{title: "Edited"}, leaving)

    summary = Brando.Users.get_user_content_summary(leaving.id)
    assert %{table: "pages", count: 1} = Enum.find(summary, &(&1.table == "pages"))

    {:ok, _} = Brando.Users.transfer_user_content(leaving.id, recipient.id)
    transferred = Brando.Repo.get!(Pages.Page, page.id)

    assert transferred.creator_id == recipient.id
    assert transferred.updated_by_id == recipient.id
  end

  test "a save that changes only derived fields is not an edit" do
    user = Factory.insert(:random_user)
    {:ok, page} = Pages.create_page(page_params(), user)

    derived_only = Ecto.Changeset.change(page, %{title: "Derived", rendered_blocks: "<p>x</p>"})
    real_edit = Ecto.Changeset.change(page, %{title: "Derived", uri: "edited"})

    unchanged = Brando.Trait.Creator.changeset_mutator(Pages.Page, %{derived: [:title]}, derived_only, user, [])
    stamped = Brando.Trait.Creator.changeset_mutator(Pages.Page, %{derived: [:title]}, real_edit, user, [])

    refute Map.has_key?(unchanged.changes, :updated_by_id)
    assert stamped.changes.updated_by_id == user.id
  end

  test "image processing results do not mark an upload as edited" do
    user = Factory.insert(:random_user)
    image = Factory.insert(:image, creator: user, status: :unprocessed)

    {:ok, processed} =
      Brando.Images.update_image(image, %{sizes: %{"thumb" => "thumb.jpg"}, formats: [:jpg], status: :processed}, user)

    assert processed.status == :processed
    assert processed.updated_by_id == nil

    {:ok, edited} = Brando.Images.update_image(processed, %{alt: "Described"}, user)
    assert edited.updated_by_id == user.id
  end
end
