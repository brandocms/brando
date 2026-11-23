defmodule BrandoAdmin.Components.Form.RelationRowsTest do
  # A form keeping its editor's rows over another editor's save
  # (`Form.take_saved_entry/1`). Rows are not merged: the form keeps its own,
  # with the saved values in the rows it didn't change.
  use ExUnit.Case, async: true

  alias Brando.Repo
  alias BrandoAdmin.Components.Form.RelationRows
  alias BrandoAdmin.Components.Form.RowEdits
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

  # An author whose links can't be replaced (Ecto's default `on_replace`)
  defmodule FixedAuthor do
    @moduledoc false
    use Ecto.Schema

    schema "synctest_article_authors" do
      field :name, :string
      field :article_id, :id
      has_many :links, Link, foreign_key: :author_id
    end

    def changeset(author, params), do: author |> Changeset.cast(params, [:name]) |> Changeset.cast_assoc(:links)
  end

  defmodule FixedArticle do
    @moduledoc false
    use Ecto.Schema

    schema "synctest_articles" do
      field :title, :string
      has_one :author, FixedAuthor, foreign_key: :article_id
      timestamps()
    end

    def changeset(article, params), do: article |> Changeset.cast(params, [:title]) |> Changeset.cast_assoc(:author)
  end

  defmodule Quote do
    @moduledoc false
    use Ecto.Schema

    embedded_schema do
      field :text, :string
      field :rank, :integer
      # Set by the changeset, not typed: a new row gets another each cast
      field :uid, :string
      field :meta, :map
    end

    def changeset(quote, params) do
      quote
      |> Changeset.cast(params, [:text, :rank])
      |> then(
        &if(Changeset.get_field(&1, :uid), do: &1, else: Changeset.put_change(&1, :uid, "#{System.unique_integer()}"))
      )
    end
  end

  # Rows stored without a key of their own
  defmodule BareQuote do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :text, :string
    end
  end

  defmodule Board do
    @moduledoc false
    use Ecto.Schema

    embedded_schema do
      embeds_many :quotes, Quote, on_replace: :delete
      embeds_many :bare_quotes, BareQuote, on_replace: :delete
      # A Blueprint's `embeds_one` default
      embeds_one :feature, Quote, on_replace: :update
    end

    def changeset(board, params, opts \\ []) do
      board
      |> Changeset.cast(params, [])
      |> Changeset.cast_embed(:quotes)
      |> Changeset.cast_embed(:feature, required: Keyword.get(opts, :required, false))
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

    # The same, with a link: the author's own rows are in the data as well.
    test "a has_one that can't be replaced takes this form's new row from its data, with its rows", c do
      base = reload(c.article, [:items, author: :links])
      held = %Author{name: "Name by B", links: [%Link{label: "Link by B"}]}
      previous = base |> Map.put(:author, held) |> Changeset.change()
      Repo.insert!(%Author{article_id: c.article.id, name: "Name by A"})
      saved = base |> reload([:items, author: :links]) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :author)

      assert [%{name: "Name by B", links: [%{label: "Link by B"}]}] = RelationRows.rows(carried, :author)
      assert {:ok, written} = Repo.update(carried)

      assert %{name: "Name by B", links: [%{label: "Link by B"}]} =
               written |> reload(author: :links) |> Map.fetch!(:author)
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

    # Both tabs fill in the author, each with a link; A saves first. The
    # author's links can't be replaced: A's stays beside B's.
    for from <- [:data, :changes] do
      test "a new has_one onto the saved one keeps the saved rows it can't replace (B's author in its #{from})", c do
        base = FixedArticle |> Repo.get!(c.article.id) |> Repo.preload(author: :links)

        previous =
          case unquote(from) do
            :data ->
              base
              |> Map.put(:author, %FixedAuthor{name: "Name by B", links: [%Link{label: "Link by B"}]})
              |> Changeset.change()

            :changes ->
              FixedArticle.changeset(base, %{
                "author" => %{"name" => "Name by B", "links" => %{"0" => %{"label" => "Link by B"}}}
              })
          end

        author = Repo.insert!(%Author{article_id: c.article.id, name: "Name by A"})
        Repo.insert!(%Link{author_id: author.id, label: "Link by A"})
        saved = FixedArticle |> Repo.get!(c.article.id) |> Repo.preload(author: :links) |> Changeset.change()

        carried = RelationRows.keep(saved, previous, base, :author)

        assert [%{name: "Name by B", links: links}] = RelationRows.rows(carried, :author)
        assert links |> Enum.map(& &1.label) |> Enum.sort() == ["Link by A", "Link by B"]
        assert {:ok, written} = Repo.update(carried)

        assert %{name: "Name by B", links: links} =
                 FixedArticle |> Repo.get!(written.id) |> Repo.preload(author: :links) |> Map.fetch!(:author)

        assert links |> Enum.map(& &1.label) |> Enum.sort() == ["Link by A", "Link by B"]
      end
    end

    # The saved author is read without its links: B's go as they are.
    test "a new has_one onto a saved one read without its rows keeps the form's rows", c do
      base = FixedArticle |> Repo.get!(c.article.id) |> Repo.preload(author: :links)
      held = %FixedAuthor{name: "Name by B", links: [%Link{label: "Link by B"}]}
      previous = base |> Map.put(:author, held) |> Changeset.change()
      Repo.insert!(%Author{article_id: c.article.id, name: "Name by A"})
      saved = FixedArticle |> Repo.get!(c.article.id) |> Repo.preload(:author) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :author)

      assert [%{name: "Name by B", links: [%{label: "Link by B"}]}] = RelationRows.rows(carried, :author)
    end

    # B's author has a value it typed that didn't cast: its error stays.
    test "a new has_one onto the saved one keeps the error of a value that didn't cast", c do
      base = reload(c.article, [:items, author: :links])
      previous = Article.changeset(base, %{"author" => %{"name" => "Name by B"}})
      previous = update_in(previous.changes.author, &Changeset.add_error(&1, :name, "is wrong"))
      Repo.insert!(%Author{article_id: c.article.id, name: "Name by A"})
      saved = base |> reload([:items, author: :links]) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :author)

      assert Keyword.has_key?(carried.changes.author.errors, :name)
      refute carried.valid?
    end

    # A relation's base (`base/2`) is its rows' content: a read that returns
    # them in another order has the same base, and a reorder another.
    test "a relation's base doesn't depend on the order the rows were read in", c do
      for {label, n} <- [{"First", 0}, {"Second", 1}],
          do: Repo.insert!(%Item{article_id: c.article.id, label: label, sequence: n})

      entry = reload(c.article, [:author, :items])
      reversed = Map.update!(entry, :items, &Enum.reverse/1)
      reordered = Map.update!(entry, :items, fn items -> Enum.map(items, &%{&1 | sequence: 1 - &1.sequence}) end)

      assert RelationRows.base(entry, :items) == RelationRows.base(reversed, :items)
      assert RelationRows.base(entry, :items) != RelationRows.base(reordered, :items)
      assert RelationRows.base(Map.put(entry, :items, %Ecto.Association.NotLoaded{}), :items) == nil
    end

    test "a relation's base doesn't depend on the order its rows' own rows were read in", c do
      author = Repo.insert!(%Author{article_id: c.article.id, name: "Author"})
      for label <- ["First", "Second"], do: Repo.insert!(%Link{author_id: author.id, label: label})

      entry = reload(c.article, [:items, author: :links])
      reversed = update_in(entry.author.links, &Enum.reverse/1)

      assert RelationRows.base(entry, :author) == RelationRows.base(reversed, :author)
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

    # B typed a value the sequence can't take; A's save removed the row
    test "a row the save removed keeps the values typed that didn't cast, and their errors", c do
      item = Repo.insert!(%Item{article_id: c.article.id, label: "Old", sequence: 4})
      base = reload(c.article, [:author, :items])

      previous =
        Article.changeset(base, %{"items" => %{"0" => %{"id" => "#{item.id}", "label" => "Old", "sequence" => "abc"}}})

      Repo.delete!(item)
      saved = base |> reload([:author, :items]) |> Changeset.change()

      carried = RelationRows.keep(saved, previous, base, :items)

      assert [row] = carried.changes.items
      assert row.action == :insert
      assert Keyword.has_key?(row.errors, :sequence)
      assert row.params["sequence"] == "abc"
      refute carried.valid?
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

  describe "an embedded list" do
    setup do
      [one, two, three] = for {id, text} <- [{"1", "One"}, {"2", "Two"}, {"3", "Three"}], do: %Quote{id: id, text: text}
      %{base: %Board{id: "b", quotes: [one, two, three]}}
    end

    # The browser's rows, in the order it sends them
    defp form_rows(rows), do: rows |> Enum.with_index() |> Map.new(fn {row, n} -> {to_string(n), row} end)

    # What the form recorded of the editor's own edits (`RowEdits`)
    defp edits(opts) do
      %{
        RowEdits.empty()
        | typed: Map.new(opts[:typed] || [], fn {key, fields} -> {key, MapSet.new(fields)} end),
          added: MapSet.new(opts[:added] || []),
          removed: MapSet.new(opts[:removed] || []),
          moved?: opts[:moved?] || false
      }
    end

    defp kept_list(saved, previous, edits, keys \\ %{}),
      do: saved |> Changeset.change() |> RelationRows.keep_list(previous, :quotes, edits(edits), keys)

    defp kept_texts(saved, previous, edits, keys \\ %{}) do
      {kept, _renamed} = kept_list(saved, previous, edits, keys)
      kept |> Changeset.get_field(:quotes) |> Enum.map(& &1.text)
    end

    defp saved_rows(base), do: for(%{id: id, text: text} <- base.quotes, do: %{"id" => id, "text" => text})

    # B moved the third row first and changed the first; A's save added a
    # row at the end, after the third, and one after the first
    test "the editor's order wins, and the rows the save added go after their neighbours", %{base: base} do
      previous =
        Board.changeset(base, %{
          "quotes" =>
            form_rows([
              %{"id" => "3", "text" => "Three"},
              %{"id" => "1", "text" => "One by B"},
              %{"id" => "2", "text" => "Two"}
            ])
        })

      [one, two, three] = base.quotes
      saved = %{base | quotes: [one, %Quote{id: "5", text: "Five by A"}, two, three, %Quote{id: "4", text: "Four by A"}]}

      assert kept_texts(saved, previous, typed: [{"id-1", [:text]}], moved?: true) ==
               ["Three", "Four by A", "One by B", "Five by A", "Two"]
    end

    # B added a row after the first and changed the third; A's save moved
    # the second row first
    test "the save's order wins when the editor moved nothing, and the editor's new row goes after its neighbour",
         %{base: base} do
      previous =
        Board.changeset(base, %{
          "quotes" =>
            form_rows([
              %{"id" => "1", "text" => "One"},
              %{"_key" => "new-b", "text" => "New by B"},
              %{"id" => "2", "text" => "Two"},
              %{"id" => "3", "text" => "Three by B"}
            ])
        })

      [one, two, three] = base.quotes
      saved = %{base | quotes: [two, one, three]}

      assert kept_texts(saved, previous, added: ["new-b"], typed: [{"id-3", [:text]}]) ==
               ["Two", "One", "New by B", "Three by B"]
    end

    # B's form holds a value another editor sent for the first row: not
    # B's edit, so the save's value wins. B's own in the second stays.
    test "a value the form only received takes the saved value", %{base: base} do
      [one, two, three] = base.quotes

      previous =
        Board.changeset(base, %{
          "quotes" =>
            form_rows([
              %{"id" => "1", "text" => "One y"},
              %{"id" => "2", "text" => "Two by B"},
              %{"id" => "3", "text" => "Three"}
            ])
        })

      saved = %{base | quotes: [%{one | text: "One z"}, two, three]}

      assert kept_texts(saved, previous, typed: [{"id-2", [:text]}]) == ["One z", "Two by B", "Three"]
    end

    test "rows without a key are kept whole", %{base: base} do
      bare = %{base | bare_quotes: [%BareQuote{text: "One"}]}
      saved = Changeset.change(bare)
      previous = Changeset.change(bare)

      assert RelationRows.embedded_rows?(saved, previous, bare, :quotes)
      refute RelationRows.embedded_rows?(saved, previous, bare, :bare_quotes)

      unsaved = %{base | quotes: [%Quote{text: "Stored without a key"}]}
      refute RelationRows.embedded_rows?(Changeset.change(unsaved), previous, base, :quotes)
      refute RelationRows.embedded_rows?(saved, previous, unsaved, :quotes)
    end

    # B added a fourth quote and typed in it; A's save wrote it, with a key
    # and a value the cast sets (`uid`) of its own, and maps B's key to it.
    test "a new row the save wrote is that saved row once, by its key", %{base: base} do
      previous =
        Board.changeset(base, %{"quotes" => form_rows(saved_rows(base) ++ [%{"_key" => "new-1", "text" => "Four on"}])})

      saved = %{base | quotes: base.quotes ++ [%Quote{id: "4", text: "Four", uid: "stored"}]}
      keys = %{"new-1" => "id-4"}

      {kept, renamed} = kept_list(saved, previous, [added: ["new-1"], typed: [{"new-1", [:text]}]], keys)
      quotes = Changeset.get_field(kept, :quotes)

      assert Enum.map(quotes, &{&1.id, &1.text}) == [{"1", "One"}, {"2", "Two"}, {"3", "Three"}, {"4", "Four on"}]
      assert [%{uid: "stored"}] = Enum.filter(quotes, &(&1.id == "4"))
      assert renamed == %{"new-1" => "id-4"}

      # Not typed in since: the row is the saved one
      assert kept_texts(saved, previous, [added: ["new-1"]], keys) == ["One", "Two", "Three", "Four"]
    end

    # Both hold only defaults: a row is told by its key, not what it holds
    test "a row B added stays a new row beside the one the save added, though both are empty", %{base: base} do
      previous = Board.changeset(base, %{"quotes" => form_rows(saved_rows(base) ++ [%{"_key" => "new-b"}])})
      saved = %{base | quotes: base.quotes ++ [%Quote{id: "4"}]}

      {kept, renamed} = kept_list(saved, previous, [added: ["new-b"]], %{"new-a" => "id-4"})

      assert kept |> Changeset.get_field(:quotes) |> Enum.map(&{&1.id, &1.text}) ==
               [{"1", "One"}, {"2", "Two"}, {"3", "Three"}, {nil, nil}, {"4", nil}]

      assert renamed == %{}
    end

    # Another editor's new row B received, which the save doesn't hold; and
    # the same with no saver's map (a rewrite no form made)
    test "a new row B only received goes unless the save has no map of its rows", %{base: base} do
      previous =
        Board.changeset(base, %{"quotes" => form_rows(saved_rows(base) ++ [%{"_key" => "new-c", "text" => "By C"}])})

      assert kept_texts(base, previous, [typed: [{"id-1", [:text]}]], %{}) == ["One", "Two", "Three"]
      assert kept_texts(base, previous, [typed: [{"id-1", [:text]}]], nil) == ["One", "Two", "Three", "By C"]
    end

    # B typed a value the rank can't take in the second row; A's save
    # removed the row.
    test "a row the save removed keeps what the editor typed that didn't cast, and its error", %{base: base} do
      [one, two, three] = base.quotes
      base = %{base | quotes: [one, %{two | rank: 4}, three]}

      previous =
        Board.changeset(base, %{
          "quotes" =>
            form_rows([
              %{"id" => "1", "text" => "One"},
              %{"id" => "2", "text" => "Two", "rank" => "abc"},
              %{"id" => "3", "text" => "Three"}
            ])
        })

      {carried, renamed} = kept_list(%{base | quotes: [one, three]}, previous, typed: [{"id-2", [:rank]}])

      assert [row] = Enum.filter(carried.changes.quotes, &(&1.action == :insert))
      assert Keyword.has_key?(row.errors, :rank)
      assert row.params["rank"] == "abc"
      refute row.valid?
      refute carried.valid?
      assert %{"id-2" => "new-" <> _} = renamed
    end

    # A shared a new row, which B removed; A saved it before B's removal
    # reached A. B's removal goes by the saved key from then on, so a save
    # with no map of its rows (a rewrite) that still holds it leaves it out.
    test "a new row the editor removed stays out after the save that wrote it", %{base: base} do
      previous = Board.changeset(base, %{"quotes" => form_rows(saved_rows(base))})
      saved = %{base | quotes: base.quotes ++ [%Quote{id: "4", text: "Four by A"}]}

      {_kept, renamed} = kept_list(saved, previous, [removed: ["new-k"]], %{"new-k" => "id-4"})
      assert renamed == %{"new-k" => "id-4"}

      edits = %{quotes: edits(removed: ["new-k"])} |> RowEdits.rename(:quotes, renamed) |> RowEdits.get(:quotes)
      {kept, _renamed} = saved |> Changeset.change() |> RelationRows.keep_list(previous, :quotes, edits, nil)

      assert kept |> Changeset.get_field(:quotes) |> Enum.map(& &1.text) == ["One", "Two", "Three"]
    end

    # A map field read back from the database has string keys; the form may
    # hold the row as written, with atom keys
    test "rows compare as stored", %{base: base} do
      [one | _] = base.quotes

      assert RelationRows.stored([%{one | meta: %{source: "a"}}]) ==
               RelationRows.stored([%{one | meta: %{"source" => "a"}}])

      refute RelationRows.stored([%{one | meta: %{source: "a"}}]) ==
               RelationRows.stored([%{one | meta: %{"source" => "b"}}])
    end
  end

  describe "an embedded one" do
    setup do
      %{base: %Board{id: "b", quotes: [], feature: %Quote{id: "f", text: "Feature"}}}
    end

    # B cleared the feature; A's save is of another field. The Blueprint's
    # `on_replace: :update` takes a removal.
    test "one the editor cleared stays cleared when the saved row is the one they removed", %{base: base} do
      previous = Board.changeset(base, %{"feature" => nil})
      assert Map.has_key?(previous.changes, :feature)

      carried = base |> Changeset.change() |> RelationRows.keep(previous, base, :feature)

      assert Changeset.get_field(carried, :feature) == nil
    end

    # A's save put another row there: B's removal was of a row gone since
    test "one the editor cleared takes the row the save put there instead", %{base: base} do
      previous = Board.changeset(base, %{"feature" => nil})
      saved = %{base | feature: %Quote{id: "g", text: "Other by A"}}

      carried = saved |> Changeset.change() |> RelationRows.keep(previous, base, :feature)

      assert %Quote{id: "g"} = Changeset.get_field(carried, :feature)
    end

    # A sent a text for the feature, which B's form took; B changed the
    # rank. A's save has another text: B keeps the rank alone.
    test "one keeps the fields the editor changed, not those it received", %{base: base} do
      previous = Board.changeset(base, %{"feature" => %{"id" => "f", "text" => "Feature by A", "rank" => "2"}})
      saved = %{base | feature: %Quote{id: "f", text: "Feature by A, on"}}
      edits = %{RowEdits.empty() | typed: %{"id-f" => MapSet.new([:rank])}}

      carried = saved |> Changeset.change() |> RelationRows.keep(previous, base, :feature, edits)

      assert %Quote{text: "Feature by A, on", rank: 2} = Changeset.get_field(carried, :feature)
    end

    # A required one cleared doesn't cast: the form keeps it as the editor
    # left it, with its error, rather than the saved row beside the error.
    test "a required one the editor cleared is kept as the form holds it", %{base: base} do
      previous = Board.changeset(base, %{"feature" => nil}, required: true)
      assert Keyword.has_key?(previous.errors, :feature)

      refute RelationRows.embedded_rows?(Changeset.change(base), previous, base, :feature)
    end
  end

  # What the form records of the editor's own edits as they make them
  describe "RowEdits" do
    setup do
      [one, two, three] = for {id, text} <- [{"1", "One"}, {"2", "Two"}, {"3", "Three"}], do: %Quote{id: id, text: text}
      %{base: %Board{id: "b", quotes: [one, two, three], feature: %Quote{id: "f", text: "Feature"}}}
    end

    test "an input in an embedded one is a field of the row the form holds", %{base: base} do
      params = %{"feature" => %{"text" => "Feature by B"}}
      previous = Changeset.change(base)
      changeset = Board.changeset(base, params)

      edits = RowEdits.typed(%{}, [:quotes, :feature], previous, changeset, ["board", "feature", "text"], params)

      assert RowEdits.get(edits, :feature).typed == %{"id-f" => MapSet.new([:text])}
    end

    # B typed in the first and second quotes and sent them; another editor
    # sends the first otherwise, and the second as B sent it
    test "a field another editor sends a value of their own for is theirs", %{base: base} do
      [one, two, three] = base.quotes
      form = Changeset.change(%{base | quotes: [%{one | text: "One by B"}, %{two | text: "Two by B"}, three]})
      edits = %{quotes: %{RowEdits.empty() | typed: %{"id-1" => MapSet.new([:text]), "id-2" => MapSet.new([:text])}}}
      theirs = [%{one | text: "One by A"}, %{two | text: "Two by B"}, three]

      assert RowEdits.get(RowEdits.received(edits, :quotes, form, theirs, false), :quotes).typed ==
               %{"id-2" => MapSet.new([:text])}

      # The form holds the list as it recovered it: every row they send is theirs
      assert RowEdits.received(edits, :quotes, form, theirs, true) == %{}
    end
  end
end
