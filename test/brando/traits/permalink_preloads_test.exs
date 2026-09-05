defmodule Brando.Trait.PermalinkPreloadsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  defmodule Entry do
    use Ecto.Schema

    schema "pages_pages" do
      field :uri, :string
      belongs_to :creator, Brando.Users.User
    end

    def has_trait(Brando.Trait.Permalink), do: true
    def __absolute_url_preloads__, do: [:creator]
    def __absolute_url__(entry), do: "/#{entry.creator.name}/#{entry.uri}"
  end

  test "compares association URLs using the persisted FK while retaining the previous association" do
    previous_user = Brando.Factory.insert(:random_user, name: "old-author")
    saved_user = Brando.Factory.insert(:random_user, name: "new-author")
    previous = %Entry{id: 1, uri: "article", creator_id: previous_user.id, creator: previous_user}
    saved = %{previous | creator_id: saved_user.id}

    assert Brando.Trait.Permalink.redirect_for(previous, saved, "en") ==
             %{from: "/old-author/article", to: "/new-author/article", code: 301, language: "en"}
  end
end
