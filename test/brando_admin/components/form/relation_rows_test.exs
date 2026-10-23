defmodule BrandoAdmin.Components.Form.RelationRowsTest do
  # A form keeping its editor's rows over another editor's save
  # (`Form.take_saved_entry/1`). Rows are not merged: the form keeps its own,
  # with the saved values in the rows it didn't change.
  use ExUnit.Case, async: true

  alias Brando.Repo
  alias BrandoAdmin.Components.Form.RelationRows
  alias Ecto.Changeset

  defmodule Tag do
    @moduledoc false
    use Ecto.Schema

    schema "tags" do
    end
  end

  defmodule Photo do
    @moduledoc false
    use Ecto.Schema

    schema "photos" do
      many_to_many :tags, Tag, join_through: "photos_to_tags", on_replace: :delete
    end

    def changeset(photo, params),
      do: Brando.M2M.cast_collection(Ecto.Changeset.cast(photo, params, []), :tags, Brando.Repo.repo(), Tag, false)
  end

  # Links that can't be replaced (Ecto's default `on_replace`)
  defmodule FixedPhoto do
    @moduledoc false
    use Ecto.Schema

    schema "photos" do
      many_to_many :tags, Tag, join_through: "photos_to_tags", join_keys: [photo_id: :id, tag_id: :id]
    end
  end

  defmodule Link do
    @moduledoc false
    use Ecto.Schema

    schema "synctest_article_author_links" do
      field :label, :string
      belongs_to :author, BrandoAdmin.Components.Form.RelationRowsTest.Author
    end

    def changeset(link, params), do: Changeset.cast(link, params, [:label])
  end

  defmodule Author do
    @moduledoc false
    use Ecto.Schema

    schema "synctest_article_authors" do
      field :name, :string
      field :article_id, :id
      has_many :links, Link, on_replace: :delete
    end

    def changeset(author, params), do: author |> Changeset.cast(params, [:name]) |> Changeset.cast_assoc(:links)
  end

  defmodule Item do
    @moduledoc false
    use Ecto.Schema

    schema "synctest_article_items" do
      field :label, :string
      field :sequence, :integer
      field :article_id, :id
    end

    def changeset(item, params), do: Changeset.cast(item, params, [:label, :sequence])
  end

  # Rows that can't be replaced (Ecto's default `on_replace`)
  defmodule Article do
    @moduledoc false
    use Ecto.Schema

    schema "synctest_articles" do
      field :title, :string
      has_one :author, Author
      has_many :items, Item, preload_order: [asc: :sequence]
      timestamps()
    end

    def changeset(article, params) do
      article
      |> Changeset.cast(params, [:title])
      |> Changeset.cast_assoc(:author)
      |> Changeset.cast_assoc(:items)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo.repo())
    [kept, added, saved] = for _ <- 1..3, do: Repo.insert!(%Tag{})
    photo = Repo.insert!(%Photo{tags: [kept]}) |> Repo.preload(:tags, force: true)
    %{photo: photo, kept: kept, added: added, saved: saved}
  end

  defp reload(%schema{id: id}, preloads), do: schema |> Repo.get!(id) |> Repo.preload(preloads, force: true)

  # B added a tag the entry didn't have (cast as an `:update` of the loaded
  # tag); A's save added another, which B's form doesn't take.
  test "a many_to_many keeps the entries this form links, not those the save added", c do
    previous = Photo.changeset(c.photo, %{"tags" => [c.kept.id, c.added.id]})
    saved = c.photo |> Ecto.Changeset.change() |> Ecto.Changeset.put_assoc(:tags, [c.kept, c.saved]) |> Repo.update!()
    saved = Ecto.Changeset.change(Repo.preload(saved, :tags, force: true))

    carried = RelationRows.keep(saved, previous, c.photo, :tags)

    assert carried |> RelationRows.rows(:tags) |> Enum.sort() == Enum.sort([[id: c.kept.id], [id: c.added.id]])
  end

  test "a many_to_many that can't replace a link keeps every saved one", c do
    base = Repo.get!(FixedPhoto, c.photo.id) |> Repo.preload(:tags)
    previous = base |> Changeset.change() |> Changeset.put_assoc(:tags, [c.kept, c.added])
    Repo.insert_all("photos_to_tags", [%{photo_id: c.photo.id, tag_id: c.saved.id}])
    saved = base |> reload(:tags) |> Changeset.change()

    carried = RelationRows.keep(saved, previous, base, :tags)

    assert carried |> RelationRows.rows(:tags) |> Enum.sort() ==
             Enum.sort([[id: c.kept.id], [id: c.added.id], [id: c.saved.id]])
  end

  # B took a tag out; A's save linked another.
  test "a many_to_many keeps the entry this form unlinked out, and leaves the one the save linked", c do
    previous = Photo.changeset(c.photo, %{"tags" => []})
    saved = c.photo |> Ecto.Changeset.change() |> Ecto.Changeset.put_assoc(:tags, [c.kept, c.saved]) |> Repo.update!()
    saved = Ecto.Changeset.change(Repo.preload(saved, :tags, force: true))

    carried = RelationRows.keep(saved, previous, c.photo, :tags)

    assert RelationRows.rows(carried, :tags) == []
    assert {:ok, written} = Repo.update(carried)
    assert written |> reload(:tags) |> Map.fetch!(:tags) == []
  end

  describe "an article" do
    setup do
      %{article: Repo.insert!(%Article{title: "Article"})}
    end

    # Both tabs fill in the author the article doesn't have; A saves first.
    # The has_one can't replace its row, so B's goes onto A's.
    test "a has_one that can't be replaced takes this form's new row as changes to the saved one", c do
      base = reload(c.article, [:author, :items])
      previous = Article.changeset(base, %{"author" => %{"name" => "Name by B"}})
      Repo.insert!(%Author{article_id: c.article.id, name: "Name by A"})
      saved = base |> reload([:author, :items]) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :author)

      assert [%{name: "Name by B"}] = RelationRows.rows(carried, :author)
      assert {:ok, written} = Repo.update(carried)
      assert [%{name: "Name by B"}] = Repo.all(Ecto.assoc(written, :author))
    end

    # B's new author is in the form's data: an asset pick applied the form's
    # changes there (`Form.commit_entry_field_asset/5`). A saved an author.
    test "a has_one that can't be replaced takes this form's new row from its data", c do
      base = reload(c.article, [:author, :items])
      previous = base |> Map.put(:author, %Author{name: "Name by B"}) |> Changeset.change()
      Repo.insert!(%Author{article_id: c.article.id, name: "Name by A"})
      saved = base |> reload([:author, :items]) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :author)

      assert [%{name: "Name by B"}] = RelationRows.rows(carried, :author)
      assert {:ok, written} = Repo.update(carried)
      assert [%{name: "Name by B"}] = Repo.all(Ecto.assoc(written, :author))
    end

    # Both tabs fill in the author the article doesn't have, B with a link;
    # A saves first.
    test "a new has_one onto the saved one keeps its own new rows", c do
      base = reload(c.article, [:items, author: :links])

      previous =
        Article.changeset(base, %{
          "author" => %{"name" => "Name by B", "links" => %{"0" => %{"label" => "Link by B"}}}
        })

      Repo.insert!(%Author{article_id: c.article.id, name: "Name by A"})
      saved = base |> reload([:items, author: :links]) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :author)

      assert [%{name: "Name by B", links: [%{label: "Link by B"}]}] = RelationRows.rows(carried, :author)
      assert {:ok, written} = Repo.update(carried)

      assert %{name: "Name by B", links: [%{label: "Link by B"}]} =
               written |> reload(author: :links) |> Map.fetch!(:author)
    end

    # The row B took out is a `:delete` changeset: a relation that can't
    # replace its rows still lets it go.
    test "rows that can't be replaced: a row this form took out stays out", c do
      [first, second] =
        for {label, n} <- [{"First", 0}, {"Second", 1}],
            do: Repo.insert!(%Item{article_id: c.article.id, label: label, sequence: n})

      base = reload(c.article, [:author, :items])

      previous =
        base
        |> Changeset.change()
        |> Changeset.put_assoc(:items, [
          Changeset.change(first),
          second |> Changeset.change() |> Map.put(:action, :delete)
        ])

      c.article |> Changeset.change(title: "Title by A") |> Repo.update!()
      saved = base |> reload([:author, :items]) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :items)

      assert carried |> RelationRows.rows(:items) |> Enum.map(& &1.label) == ["First"]
      assert {:ok, written} = Repo.update(carried)
      assert written |> reload(:items) |> Map.fetch!(:items) |> Enum.map(& &1.label) == ["First"]
    end

    # B typed a label and a value the field can't take (left as typed, with
    # its error); A's save is of the title.
    test "a row's edit carries the values typed that didn't cast, and their errors", c do
      item = Repo.insert!(%Item{article_id: c.article.id, label: "Old", sequence: 0})
      base = reload(c.article, [:author, :items])

      previous =
        Article.changeset(base, %{
          "items" => %{"0" => %{"id" => "#{item.id}", "label" => "Row by B", "sequence" => "1.5"}}
        })

      c.article |> Changeset.change(title: "Title by A") |> Repo.update!()
      saved = base |> reload([:author, :items]) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :items)

      assert [row] = carried.changes.items
      assert Keyword.has_key?(row.errors, :sequence)
      refute carried.valid?

      [shown] =
        carried
        |> Phoenix.Component.to_form()
        |> Map.fetch!(:source)
        |> then(&Phoenix.HTML.FormData.to_form(&1, Phoenix.Component.to_form(&1), :items, []))

      assert shown[:label].value == "Row by B"
      assert shown[:sequence].value == "1.5"
    end

    test "rows that can't be replaced: this form's edit in one, the save's in another", c do
      [first, second] =
        for {label, n} <- [{"Old", 0}, {"Second", 1}],
            do: Repo.insert!(%Item{article_id: c.article.id, label: label, sequence: n})

      base = reload(c.article, [:author, :items])

      previous =
        Article.changeset(base, %{
          "items" => %{
            "0" => %{"id" => "#{first.id}", "label" => "Row 0 by B"},
            "1" => %{"id" => "#{second.id}", "label" => "Second"}
          }
        })

      second |> Changeset.change(label: "Row 1 by A") |> Repo.update!()
      Repo.insert!(%Item{article_id: c.article.id, label: "Added by A", sequence: 2})
      saved = base |> reload([:author, :items]) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :items)

      # The form shows them so: the rows it renders are the ones it saves.
      assert carried |> RelationRows.rows(:items) |> Enum.map(& &1.label) == ["Row 0 by B", "Row 1 by A", "Added by A"]
      assert {:ok, written} = Repo.update(carried)

      assert written |> reload(:items) |> Map.fetch!(:items) |> Enum.map(& &1.label) == [
               "Row 0 by B",
               "Row 1 by A",
               "Added by A"
             ]
    end

    # B's change is in a row of a relation of the author (a multi-select or
    # nested rows in a subform row); A's save changed the author's name.
    test "a change in a row's own relation is this form's, and is carried", c do
      author = Repo.insert!(%Author{article_id: c.article.id, name: "Old name"})
      link = Repo.insert!(%Link{author_id: author.id, label: "Old link"})
      base = reload(c.article, [:items, author: :links])

      previous =
        Article.changeset(base, %{
          "author" => %{
            "id" => "#{author.id}",
            "name" => "Old name",
            "links" => %{"0" => %{"id" => "#{link.id}", "label" => "Link by B"}}
          }
        })

      assert RelationRows.rows(previous, :author) != RelationRows.rows(Changeset.change(base), :author)

      author |> Changeset.change(name: "Name by A") |> Repo.update!()
      saved = base |> reload([:items, author: :links]) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :author)

      assert {:ok, written} = Repo.update(carried)

      assert %{name: "Name by A", links: [%{label: "Link by B"}]} =
               written |> reload(author: :links) |> Map.fetch!(:author)
    end
  end
end
