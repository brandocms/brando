defmodule Brando.Trait.ScheduledPublishingTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page

  setup do
    {:ok, user: Factory.insert(:random_user)}
  end

  test "publishing through the context stamps publish_at", %{user: user} do
    {:ok, page} = Pages.create_page(Factory.params_for(:page, status: :draft, publish_at: nil), user)
    assert page.publish_at == nil

    {:ok, published} = Pages.update_page(page.id, %{status: :published}, user)

    assert %DateTime{} = published.publish_at
    assert {:ok, %{publish_at: %DateTime{}}} = Pages.get_page(page.id)
  end

  test "an existing publish_at is kept", %{user: user} do
    publish_at = ~U[2020-01-01 12:00:00Z]
    {:ok, page} = Pages.create_page(Factory.params_for(:page, status: :draft, publish_at: publish_at), user)

    {:ok, published} = Pages.update_page(page.id, %{status: :published}, user)

    assert published.publish_at == publish_at
  end

  test "a changeset that is not written does not stamp publish_at" do
    changeset = Page.changeset(%Page{status: :draft}, %{status: :published}, :system)

    assert Ecto.Changeset.get_change(changeset, :status) == :published
    assert Ecto.Changeset.get_field(changeset, :publish_at) == nil
  end
end
