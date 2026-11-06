defmodule Brando.PublisherPendingRightTest do
  # Pending is a request to publish that `Brando.Publisher.sweep/1` carries out
  # as the system once the date has come, so setting it takes the publish
  # right, as publishing does. Who may publish keeps pending as it was.
  # Grouped, one at a time: it takes the authorization lock (Brando.Authorization.Groups.lock!/0),
  # which a test's sandbox transaction holds until the test ends
  use ExUnit.Case, async: true, group: :shared_locks
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page

  @writer ~w(brando.admin.access brando.pages.read brando.pages.update brando.pages.create brando.pages.duplicate)
  @scheduler ~w(brando.admin.access brando.pages.read brando.pages.update brando.pages.schedule)
  @publisher ~w(brando.admin.access brando.pages.read brando.pages.update brando.pages.create
                brando.pages.publish brando.pages.schedule)

  defp at(seconds), do: DateTime.utc_now() |> DateTime.add(seconds) |> DateTime.truncate(:second)

  defp page(creator, attrs) do
    Factory.insert(
      :page,
      Keyword.merge(
        [creator: creator, uri: "pending-#{System.unique_integer([:positive])}", status: :draft, publish_at: nil],
        attrs
      )
    )
  end

  defp sweep, do: Brando.Publisher.sweep(now: at(600))

  defp status(page), do: Repo.get!(Page, page.id).status

  describe "groups" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Boundary.put_scope(nil)
      owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {:ok, _} = Migration.run()
      scope = Scope.standalone(owner)

      member = fn name, keys ->
        user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
        {:ok, group} = Groups.create(scope, %{name: name}, keys)
        {:ok, :ok} = Groups.add_member(scope, group.id, user.id)
        user
      end

      %{
        owner: owner,
        writer: member.("Writers", @writer),
        scheduler: member.("Schedulers", @scheduler),
        publisher: member.("Publishers", @publisher)
      }
    end

    test "a user without publish can't set an entry that was taken down to pending", c do
      page = page(c.owner, status: :disabled, publish_at: at(-3600))

      assert {:error, :forbidden} = Pages.update_page(page, %{status: :pending}, c.writer)
      assert {:error, :forbidden} = Brando.Trait.Status.update_status(Page, page.id, :pending, c.writer)
      assert status(page) == :disabled

      sweep()
      assert status(page) == :disabled
    end

    test "a user with schedule but not publish can't set pending in one save or two", c do
      draft = page(c.owner, [])

      assert {:error, :forbidden} = Pages.update_page(draft, %{status: :pending, publish_at: at(-3600)}, c.scheduler)
      assert {:error, :forbidden} = Pages.update_page(draft, %{status: :published, publish_at: at(3600)}, c.scheduler)

      assert {:ok, dated} = Pages.update_page(draft, %{publish_at: at(-3600)}, c.scheduler)
      assert dated.status == :draft
      assert {:error, :forbidden} = Pages.update_page(dated, %{status: :pending}, c.scheduler)

      sweep()
      assert status(draft) == :draft
    end

    test "a copy of a published page has no date, and the sweep leaves it alone", c do
      source = page(c.owner, status: :published, publish_at: at(-3600))

      assert {:ok, copy} = Pages.duplicate_page(source.id, c.writer)
      assert {copy.status, copy.publish_at} == {:draft, nil}
      assert {:error, :forbidden} = Pages.update_page(copy, %{status: :pending}, c.writer)

      sweep()
      assert status(copy) == :draft
    end

    test "a writer still edits, and may withdraw, an entry a publisher set pending", c do
      {:ok, pending} = Pages.update_page(page(c.owner, []), %{status: :published, publish_at: at(3600)}, c.publisher)
      assert pending.status == :pending

      assert {:ok, edited} = Pages.update_page(pending, %{title: "Edited"}, c.writer)
      assert {edited.status, edited.title} == {:pending, "Edited"}
      assert {:ok, %{status: :draft}} = Pages.update_page(edited, %{status: :draft}, c.writer)
    end

    test "who may publish sets pending, and the sweep publishes it", c do
      page = page(c.owner, publish_at: at(-3600))

      assert {:ok, %{status: :pending}} = Pages.update_page(page, %{status: :pending}, c.publisher)
      {1, _} = Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [publish_at: at(-3600)])

      sweep()
      assert status(page) == :published
    end
  end

  describe "legacy" do
    test "an editor sets pending, and a copy has no date" do
      editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      page = page(editor, publish_at: at(-3600))

      assert {:ok, %{status: :pending}} = Pages.update_page(page, %{status: :pending}, editor)
      assert {:ok, %{status: :draft, publish_at: nil}} = Pages.duplicate_page(page.id, editor)
    end
  end
end
