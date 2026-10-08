defmodule Brando.SearchTest do
  use ExUnit.Case
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.ContentEvents.Event
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Search
  alias Brando.Search.Document
  alias Brando.Search.Highlight
  alias Brando.Search.Query
  alias Brando.Villain.Blocks
  alias Brando.Worker.SearchIndexer
  alias Brando.Worker.SearchIndexRebuild
  alias Ecto.Changeset

  setup do
    put_test_env(Brando.ContentEvents, debounce_seconds: 0)
    {:ok, %{user: Factory.insert(:random_user)}}
  end

  defp create_page(user, attrs \\ %{}) do
    {:ok, page} =
      Pages.create_page(
        Map.merge(
          %{
            title: "About",
            uri: "about-#{System.unique_integer([:positive])}",
            language: "en",
            template: "default.html",
            status: :draft
          },
          attrs
        ),
        user
      )

    page
  end

  defp document(page), do: Repo.one(from(d in Document, where: d.schema == ^Page and d.entry_id == ^page.id))
  defp documents, do: Repo.all(from(d in Document, select: d.entry_id))

  defp search(text, opts \\ []) do
    Document |> Query.run(text, opts) |> Map.fetch!(:rows) |> Enum.map(& &1.title)
  end

  defp insert_block(page, user, attrs) do
    %Page.Blocks{}
    |> Changeset.change(%{entry_id: page.id, sequence: Map.get(attrs, :sequence, 0)})
    |> Changeset.put_assoc(
      :block,
      Map.merge(
        %{
          uid: "B#{System.unique_integer([:positive])}",
          type: :module,
          active: true,
          source: "Elixir.Brando.Pages.Page.Blocks",
          creator_id: user.id,
          sequence: 0,
          vars: [],
          refs: [],
          children: []
        },
        Map.delete(attrs, :sequence)
      )
    )
    |> Repo.insert!()
  end

  defp text_ref(text), do: %Blocks.TextBlock{type: "text", data: %Blocks.TextBlock.Data{text: text}}

  describe "kept up to date by content events" do
    test "created, updated, unpublished, trashed and restored", %{user: user} do
      page = create_page(user, %{title: "Sommerro", meta_description: "A hotel by the fjord"})

      assert %Document{title: "Sommerro", status: :draft, language: "en", config: "english"} = document(page)
      assert search("fjord") == ["Sommerro"]

      {:ok, _} = Pages.update_page(page.id, %{title: "Sommerro reopened", status: :published}, user)
      assert %Document{title: "Sommerro reopened", status: :published} = document(page)

      {:ok, _} = Pages.update_page(page.id, %{status: :draft}, user)
      assert %Document{status: :draft} = document(page)

      {:ok, trashed} = Pages.delete_page(page.id, user)
      assert document(page) == nil
      assert search("sommerro") == []

      {:ok, _} = Brando.Authorization.Boundary.restore(user, trashed)
      assert %Document{title: "Sommerro reopened"} = document(page)
    end

    test "a repeated event is harmless and reads the entry as it is now", %{user: user} do
      page = create_page(user, %{title: "Sommerro"})

      event = %Event{
        id: Ecto.UUID.generate(),
        type: "entry.updated",
        occurred_at: DateTime.utc_now(),
        schema: Page,
        entry_id: page.id
      }

      Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [title: "Changed behind its back"])
      assert :ok = Search.handle_event(event)
      assert :ok = Search.handle_event(event)

      assert [%Document{title: "Changed behind its back"}] =
               Repo.all(from(d in Document, where: d.entry_id == ^page.id))

      # A deleted event for an entry that is still there keeps its document:
      # the entry decides, not the event.
      assert :ok = Search.handle_event(%{event | type: "entry.deleted"})
      assert document(page)

      Repo.delete_all(from(p in Page, where: p.id == ^page.id))
      assert :ok = Search.handle_event(%{event | id: Ecto.UUID.generate(), type: "entry.deleted"})
      assert document(page) == nil
    end

    test "entries changing language leave no document in the old one", %{user: user} do
      page = create_page(user, %{title: "Sommerro"})
      {:ok, _} = Pages.update_page(page.id, %{language: "no"}, user)

      assert [%Document{language: "no", config: "norwegian"}] =
               Repo.all(from(d in Document, where: d.entry_id == ^page.id))
    end

    test "nothing is queued when the index is turned off", %{user: user} do
      put_test_env(Brando.Search, enabled: false)
      page = create_page(user)
      assert document(page) == nil
      refute Brando.Search in Brando.ContentEvents.subscribers()
    end

    test "the indexer job runs in the tenant it was queued in and cancels unknown types", %{user: user} do
      page = Factory.insert(:page, title: "Sommerro", creator: user)
      assert :ok = perform_job(SearchIndexer, %{"schema" => to_string(Page), "entry_id" => page.id})
      assert document(page)

      assert {:cancel, :unknown_schema} =
               perform_job(SearchIndexer, %{"schema" => "Elixir.Nope.Nothing", "entry_id" => 1})
    end
  end

  describe "what is indexed" do
    test "the body has the text fields and every kind of block text", %{user: user} do
      page = Factory.insert(:page, title: "Hotel", creator: user)
      image = Factory.insert(:image, alt: %{"en" => "A balcony at dusk"}, title: %{"en" => "Caption of the balcony"})

      insert_block(page, user, %{
        sequence: 0,
        vars: [
          %{type: :string, key: "kicker", label: "Kicker", value: "Kicker line", sequence: 0},
          %{type: :html, key: "body", label: "Body", value: "<p>Rich <strong>var</strong> text</p>", sequence: 1},
          %{type: :boolean, key: "flag", label: "Flag", value: "true", sequence: 2}
        ],
        refs: [
          %{
            name: "text",
            uid: "r1",
            sequence: 0,
            data: text_ref("<p>Paragraph with <em>emphasis</em></p><ul><li>First item</li></ul>")
          },
          %{
            name: "header",
            uid: "r2",
            sequence: 1,
            data: %Blocks.HeaderBlock{type: "header", data: %Blocks.HeaderBlock.Data{text: "A heading", level: 2}}
          },
          %{
            name: "picture",
            uid: "r3",
            sequence: 2,
            image_id: image.id,
            data: %Blocks.PictureBlock{type: "picture", data: %Blocks.PictureBlock.Data{}}
          },
          %{name: "hidden", uid: "r4", sequence: 3, active: false, data: text_ref("Inactive ref")},
          %{
            name: "code",
            uid: "r5",
            sequence: 4,
            data: %Blocks.SvgBlock{type: "svg", data: %Blocks.SvgBlock.Data{code: "<svg>secret</svg>"}}
          }
        ],
        table_rows: [
          %{sequence: 0, vars: [%{type: :string, key: "cell", label: "Cell", value: "Table cell", sequence: 0}]}
        ]
      })

      insert_block(page, user, %{
        sequence: 1,
        active: false,
        vars: [%{type: :string, key: "k", label: "K", value: "Inactive block", sequence: 0}]
      })

      container =
        insert_block(page, user, %{
          sequence: 2,
          type: :container,
          children: [
            %{
              uid: "child",
              type: :module,
              active: true,
              source: "Elixir.Brando.Pages.Page.Blocks",
              creator_id: user.id,
              sequence: 0,
              vars: [%{type: :text, key: "t", label: "T", value: "Nested child text", sequence: 0}]
            }
          ]
        })

      assert container
      :ok = Search.index_entry(Page, page.id)
      body = Repo.one(from(d in Document, where: d.entry_id == ^page.id, select: d.body))

      for text <- [
            "Kicker line",
            "Rich var text",
            "Paragraph with emphasis",
            "First item",
            "A heading",
            "A balcony at dusk",
            "Caption of the balcony",
            "Table cell",
            "Nested child text"
          ] do
        assert body =~ text
      end

      refute body =~ "Inactive"
      refute body =~ "secret"
      refute body =~ "true"
      refute body =~ "<"
    end

    test "the body is cut at about 200 KB, on a character boundary" do
      text = String.duplicate("æ", 150_000)
      capped = Brando.Search.Text.cap(text)
      assert byte_size(capped) <= Brando.Search.Text.max_bytes()
      assert String.valid?(capped)
    end

    test "control characters never reach the index, so they cannot fake a highlight" do
      assert Brando.Search.Text.plain("a\u0002b\u0003c") == "abc"
    end
  end

  describe "ranking" do
    setup %{user: user} do
      for {title, status, body} <- [
            {"Hotel Sommerro", :published, ""},
            {"Sommerro rooftop", :draft, ""},
            {"Sommerro", :draft, ""},
            {"A spa", :published, "Opened at Sommerro in May"},
            {"An older spa", :published, "Also at Sommerro"}
          ] do
        page = create_page(user, %{title: title, status: status, meta_description: body})
        page
      end

      :ok
    end

    test "an exact title, then titles starting with the text, then the content" do
      assert ["Sommerro", "Sommerro rooftop" | rest] = search("sommerro")
      assert Enum.sort(rest) == ["A spa", "An older spa", "Hotel Sommerro"]
      assert hd(rest) == "Hotel Sommerro", "a title match ranks above the description"
    end

    test "a word half typed matches" do
      assert "Sommerro" in search("somm")
    end

    test "published before drafts of the same rank, then the most recently updated" do
      Repo.update_all(from(d in Document, where: d.title == "An older spa"), set: [updated_at: ~N[2020-01-01 00:00:00]])
      Repo.update_all(from(d in Document, where: d.title == "A spa"), set: [status: 0])

      assert search("spa") == ["An older spa", "A spa"]
    end

    test "web search syntax: phrases and leaving words out" do
      assert search(~s("opened at sommerro")) == ["A spa"]
      assert "A spa" not in search("sommerro -opened")
    end

    test "filters: language, status and type" do
      assert search("sommerro", status: :draft) == ["Sommerro", "Sommerro rooftop"]
      assert search("sommerro", language: "no") == []
      assert search("sommerro", schemas: [Brando.Pages.Fragment]) == []
    end

    test "the counts per type and the total" do
      result = Query.run(Document, "sommerro", limit: 2)
      assert result.total == 5
      assert result.facets == %{Page => 5}
      assert length(result.rows) == 2
      assert Query.run(Document, "sommerro", limit: 2, offset: 4).rows |> length() == 1
    end

    test "nothing to search for finds nothing" do
      assert Query.run(Document, "  ", []).total == 0
      assert Query.run(Document, "!!!", []).total == 0
    end
  end

  describe "highlighting" do
    test "the snippet marks the match and keeps markup as text", %{user: user} do
      create_page(user, %{title: "<script>alert(1)</script> Sommerro", meta_description: "<b>Bold</b> fjord"})
      [row] = Query.run(Document, "fjord", []).rows

      # A title is text: what looks like a tag stays text, to be escaped
      assert row.title == "<script>alert(1)</script> Sommerro"
      assert {:mark, "fjord"} in row.snippet
      assert Highlight.text(row.snippet) =~ "Bold fjord"
    end

    test "segments never contain the markers, and an unpaired marker is dropped" do
      assert Highlight.segments("a \u0002hit\u0003 <b>") == [{:text, "a "}, {:mark, "hit"}, {:text, " <b>"}]
      assert Highlight.segments("\u0003x\u0002y") == [{:text, "x"}, {:text, "y"}]
    end
  end

  describe "rebuild" do
    test "indexes every entry again and removes documents nothing has", %{user: user} do
      page = Factory.insert(:page, title: "Never saved through a context", creator: user)
      trashed = Factory.insert(:page, title: "In the trash", creator: user, deleted_at: DateTime.utc_now(:second))

      Repo.query!("""
      INSERT INTO search_documents (schema, entry_id, language, config, title, indexed_at, document)
      VALUES ('Elixir.Brando.Pages.Page', 999999, 'en', 'english', 'Gone', '2020-01-01', to_tsvector('gone'))
      """)

      Phoenix.PubSub.subscribe(Brando.pubsub(), Search.topic())
      assert {:ok, %Oban.Job{}} = Search.queue_rebuild(user)

      assert page.id in documents()
      refute trashed.id in documents()
      refute 999_999 in documents()
      assert_received {:search_index, %{state: :running}}
      assert_received {:search_index, %{state: :done, done: count, total: count}}
      refute Search.rebuild_running?()
    end

    test "the rebuild job reports a failure" do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Search.topic())
      Repo.query!("ALTER TABLE search_documents RENAME TO search_documents_away")
      assert {:cancel, :no_table} = perform_job(SearchIndexRebuild, %{})
      assert_received {:search_index, %{state: :failed}}
    end
  end
end
