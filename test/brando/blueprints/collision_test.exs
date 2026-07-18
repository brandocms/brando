defmodule Brando.Blueprint.CollisionTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Blueprint.Collision
  alias Brando.Blueprint.Unique
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Ecto.Changeset

  test "arity-one collision callbacks supply the candidate query" do
    user = Factory.insert(:random_user)
    _existing_page = Factory.insert(:page, creator: user, language: :en, uri: "callback-scope")

    collision_scope = fn changeset ->
      send(self(), :collision_scope_called)
      language = Changeset.get_field(changeset, :language)
      from page in Page, where: page.language == ^language
    end

    attribute = %{
      name: :uri,
      opts: %{unique: [prevent_collision: collision_scope]}
    }

    changeset =
      %Page{}
      |> Changeset.change(%{
        creator_id: user.id,
        language: :en,
        status: :published,
        template: "default.html",
        title: "Callback scope",
        uri: "callback-scope"
      })
      |> Unique.run_unique_attribute_constraints(Page, [attribute])

    assert {:ok, page} = Brando.Repo.insert(changeset)
    assert page.uri == "callback-scope-1"
    assert_received :collision_scope_called
  end

  test "changing only a collision scope reevaluates the unique field" do
    user = Factory.insert(:random_user)
    _english_page = Factory.insert(:page, creator: user, language: :en, uri: "shared-scope")
    norwegian_page = Factory.insert(:page, creator: user, language: :no, uri: "shared-scope")

    changeset = Page.changeset(norwegian_page, %{language: :en}, user)

    assert {:ok, updated_page} = Brando.Repo.update(changeset)
    assert updated_page.language == :en
    assert updated_page.uri == "shared-scope-1"
  end

  test "a persisted entry does not collide with itself" do
    page = Factory.insert(:page)

    changeset =
      page
      |> Changeset.change()
      |> Changeset.force_change(:uri, page.uri)
      |> Collision.avoid_field_collision([:uri])

    assert {:ok, updated_page} = Brando.Repo.update(changeset)
    assert updated_page.uri == page.uri
  end
end
