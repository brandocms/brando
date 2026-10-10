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

  doctest Brando.Search.Highlight

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

  describe "tenancy" do
    @prefix "tenant_search_other"

    setup do
      put_test_env(:tenancy_mode, :multi)
      Repo.query!(~s(CREATE SCHEMA "#{@prefix}"))

      # The tables an entry is read with: the page, its blocks and alternates,
      # and the site's identity and SEO for its identifier
      %{rows: tables} =
        Repo.query!(
          "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND (tablename LIKE 'pages%' OR tablename LIKE 'content_%' OR tablename LIKE 'sites_%' OR tablename = 'search_documents')"
        )

      for [table] <- tables do
        Repo.query!(~s|CREATE TABLE "#{@prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|)
      end

      on_exit(fn -> Brando.Tenant.put_prefix(nil) end)
      :ok
    end

    test "documents are written to and found in the current site and environment only", %{user: user} do
      public = Factory.insert(:page, title: "Sommerro public", creator: user)
      :ok = Search.index_entry(Page, public.id)

      Brando.Tenant.with_prefix(@prefix, fn ->
        page =
          Brando.Repo.insert!(%Page{
            title: "Sommerro tenant",
            uri: "sommerro",
            language: :en,
            status: :published,
            template: "default.html",
            creator_id: user.id
          })

        :ok = Search.index_entry(Page, page.id)
        assert Document |> Query.run("sommerro") |> Map.fetch!(:rows) |> Enum.map(& &1.title) == ["Sommerro tenant"]

        assert {:ok, 1} = Search.rebuild()
        assert Brando.Repo.aggregate(Document, :count) == 1
        assert %DateTime{} = Search.rebuilt_at()
      end)

      assert search("sommerro") == ["Sommerro public"]
      assert Search.rebuilt_at() == nil

      assert Repo.query!(~s|SELECT title FROM "#{@prefix}".search_documents|).rows == [["Sommerro tenant"]]
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

    # Two editors asking at once both find no rebuild queued; the second
    # insert joins the first instead of rebuilding twice.
    test "two rebuilds asked for at once queue one", %{user: user} do
      test = self()
      calls = :counters.new(1, [])
      handler = "search-rebuild-race-#{System.unique_integer([:positive])}"

      # The other editor's request lands between this one's check and its insert.
      :telemetry.attach(
        handler,
        [:oban, :engine, :insert_job, :start],
        fn _event, _measurements, %{changeset: changeset}, _config ->
          if self() == test and Ecto.Changeset.get_field(changeset, :worker) == "Brando.Worker.SearchIndexRebuild" and
               :counters.get(calls, 1) == 0 do
            :counters.add(calls, 1, 1)
            Search.queue_rebuild(user)
          end
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Oban.Job{}} = Search.queue_rebuild(user)
        assert [_one] = all_enqueued(worker: SearchIndexRebuild)
      end)
    end

    test "records when it finished, and saves do not count", %{user: user} do
      page = Factory.insert(:page, title: "Saved", creator: user)
      assert Search.rebuilt_at() == nil

      :ok = Search.index_entry(Page, page.id)
      assert Search.rebuilt_at() == nil

      started = DateTime.utc_now(:second)
      assert {:ok, _count} = Search.rebuild()
      rebuilt_at = Search.rebuilt_at()
      assert DateTime.compare(rebuilt_at, started) in [:eq, :gt]
      assert DateTime.diff(DateTime.utc_now(), rebuilt_at) < 60

      # Kept with the table, not in Oban's jobs, so pruning them loses nothing
      assert %{rows: [[comment]]} = Repo.query!("SELECT obj_description('search_documents'::regclass, 'pg_class')")
      assert comment == Jason.encode!(%{"rebuilt_at" => DateTime.to_iso8601(rebuilt_at)})

      :ok = Search.index_entry(Page, page.id)
      assert Search.rebuilt_at() == rebuilt_at
    end

    test "a comment Brando did not write, or no table, is never rebuilt" do
      Repo.query!("COMMENT ON TABLE search_documents IS 'Kept by the DBA'")
      assert Search.rebuilt_at() == nil

      :ok = Search.Indexer.mark_rebuilt(~U[2026-10-01 08:30:00.123456Z])
      assert Search.rebuilt_at() == ~U[2026-10-01 08:30:00Z]

      Repo.query!("ALTER TABLE search_documents RENAME TO search_documents_away")
      assert Search.rebuilt_at() == nil
    end

    test "the rebuild job reports a failure" do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Search.topic())
      Repo.query!("ALTER TABLE search_documents RENAME TO search_documents_away")
      assert {:cancel, :no_table} = perform_job(SearchIndexRebuild, %{})
      assert_received {:search_index, %{state: :failed}}
    end
  end
end
