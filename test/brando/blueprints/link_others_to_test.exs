defmodule Brando.Blueprint.LinkOthersToTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Content.Identifier
  alias Brando.Content.Var
  alias Brando.LinkTest.Case
  alias BrandoAdmin.Components.Content.Identifier, as: IdentifierRow
  alias BrandoAdmin.Components.Content.SelectIdentifier

  defp insert_case(attrs) do
    case_entry =
      %Case{title: "Client work", slug: "client-work", type: :external_link, external_link: "client.example/work"}
      |> struct(attrs)
      |> Brando.Repo.insert!()

    {:ok, identifier} = Brando.Content.create_identifier(Case, case_entry)
    {case_entry, identifier}
  end

  defp change_case(case_entry, changes) do
    case_entry = case_entry |> Ecto.Changeset.change(changes) |> Brando.Repo.update!()
    {:ok, identifier} = Brando.Content.update_identifier(Case, case_entry)
    {case_entry, identifier}
  end

  defp link_var(identifier), do: %Var{type: :link, link_type: :identifier, identifier: identifier}

  describe "the blueprint" do
    test "a case linked elsewhere has no URL here, but a link destination" do
      linked = %Case{slug: "work", type: :external_link, external_link: "client.example/work"}

      assert Case.__absolute_url__(linked) == nil
      refute Case.__has_url__(linked)
      assert Case.__url_filter__() == %{type: :full_case}
      assert Case.__external_url__(linked) == "https://client.example/work"
    end

    test "a full case has its page and no external destination" do
      full = %Case{slug: "work", type: :full_case, external_link: "https://client.example"}

      assert Case.__absolute_url__(full) == "/cases/work"
      assert Case.__external_url__(full) == nil
    end

    test "an empty or unsafe destination is none" do
      assert Case.__external_url__(%Case{type: :external_link, external_link: nil}) == nil
      assert Case.__external_url__(%Case{type: :external_link, external_link: " "}) == nil
      assert Case.__external_url__(%Case{type: :external_link, external_link: "javascript:alert(1)"}) == nil
    end

    test "is left out of the sitemap and the SEO audit" do
      linked = %Case{slug: "work", type: :external_link, external_link: "https://client.example"}

      refute Brando.Blueprint.URL.has_url?(linked)
      refute Brando.SEO.Audit.has_url?(Case, linked)

      assert [%{loc: "/cases/full"}] ==
               [linked, %Case{slug: "full", type: :full_case}]
               |> Enum.map(&%{loc: Case.__absolute_url__(&1)})
               |> Brando.Sitemap.reject_without_loc(:cases)
               |> Enum.to_list()
    end

    test "link_others_to: needs only: and a field name" do
      assert_raise Brando.Exception.BlueprintError, ~r/link_others_to:/, fn ->
        Code.compile_string("""
        defmodule Brando.Blueprint.LinkOthersToTest.WithoutOnly do
          import Brando.Blueprint.AbsoluteURL
          absolute_url "/x", link_others_to: :external_link
        end
        """)
      end

      for value <- [~s("external_link"), "true"] do
        assert_raise Brando.Exception.BlueprintError, ~r/names a field/, fn ->
          Code.compile_string("""
          defmodule Brando.Blueprint.LinkOthersToTest.NotAField do
            import Brando.Blueprint.AbsoluteURL
            absolute_url "/x", only: %{type: :full_case}, link_others_to: #{value}
          end
          """)
        end
      end

      assert_raise Brando.Exception.BlueprintError, ~r/:external_lnk is not a field/, fn ->
        Code.compile_string("""
        defmodule Brando.Blueprint.LinkOthersToTest.Misspelt do
          use Ecto.Schema
          import Brando.Blueprint.AbsoluteURL

          schema "misspelt" do
            field :type, :string
            field :external_link, :string
          end

          absolute_url "/x", only: %{type: "full"}, link_others_to: :external_lnk
        end
        """)
      end
    end
  end

  describe "the identifier" do
    test "stores the destination apart from the URL" do
      {_case_entry, identifier} = insert_case(%{})

      assert identifier.url == nil
      assert identifier.external_url == "https://client.example/work"
      assert Identifier.link_url(identifier) == "https://client.example/work"
    end

    test "follows an edited destination and a switch to a full case" do
      {case_entry, _identifier} = insert_case(%{})

      {case_entry, identifier} = change_case(case_entry, external_link: "https://elsewhere.example")
      assert Identifier.link_url(identifier) == "https://elsewhere.example"

      {_case_entry, identifier} = change_case(case_entry, type: :full_case)
      assert identifier.url == "/cases/client-work"
      assert identifier.external_url == nil
      assert Identifier.link_url(identifier) == "/cases/client-work"
    end

    test "rewrites stored rich-text links when the destination changes" do
      {target, identifier} = insert_case(%{})

      summary = ~s(<p>See <a href="https://client.example/work" data-identifier-id="#{identifier.id}">the work</a></p>)
      holder = Brando.Repo.insert!(%Case{title: "Holder", slug: "holder", type: :full_case, summary: summary})

      change_case(target, type: :full_case)
      assert Brando.Repo.get!(Case, holder.id).summary =~ ~s(href="/cases/client-work")

      change_case(Brando.Repo.get!(Case, target.id), type: :external_link)
      assert Brando.Repo.get!(Case, holder.id).summary =~ ~s(href="https://client.example/work")

      # Nowhere to link to leaves the stored links as they are, not "#"
      change_case(Brando.Repo.get!(Case, target.id), external_link: nil)
      assert Brando.Repo.get!(Case, holder.id).summary =~ ~s(href="https://client.example/work")
    end
  end

  test "a rich-text link rewritten queues its entries' renders in the bulk lane" do
    {_target, identifier} = insert_case(%{})
    summary = ~s(<p><a href="https://client.example/work" data-identifier-id="#{identifier.id}">the work</a></p>)

    holders =
      for n <- 1..2,
          do: Brando.Repo.insert!(%Case{title: "Holder #{n}", slug: "holder-#{n}", type: :full_case, summary: summary})

    Oban.Testing.with_testing_mode(:manual, fn ->
      Brando.Content.Blocks.update_identifier_links_in_rich_text_fields(identifier.id, "/cases/client-work")

      jobs = all_enqueued(worker: Brando.Worker.EntryRenderer)
      assert Enum.sort(Enum.map(jobs, & &1.args["entry_id"])) == Enum.map(holders, & &1.id)
      assert Enum.all?(jobs, &(&1.priority == Brando.Content.RenderQueue.bulk_priority()))
    end)
  end

  describe "rich text in subform rows" do
    alias Brando.LinkTest.Chapter
    alias Brando.LinkTest.Highlight

    defp linked_html(identifier, text \\ "the work"),
      do: ~s(<p><a href="https://client.example/work" data-identifier-id="#{identifier.id}">#{text}</a></p>)

    defp rewrite(identifier, url) do
      Oban.Testing.with_testing_mode(:manual, fn ->
        Brando.Content.Blocks.update_identifier_links_in_rich_text_fields(identifier.id, url)
        all_enqueued(worker: Brando.Worker.EntryRenderer)
      end)
    end

    test "an embeds_many and an embeds_one row get the new address, other rows and fields keep theirs" do
      {_target, identifier} = insert_case(%{})
      {_other_target, other} = insert_case(%{slug: "other"})

      holder =
        Brando.Repo.insert!(%Case{
          title: "Holder",
          slug: "holder",
          type: :full_case,
          highlights: [
            %Highlight{title: "Linked", body: linked_html(identifier)},
            %Highlight{title: "Elsewhere", body: linked_html(other, "other")}
          ],
          lead: %Highlight{title: "Lead", body: linked_html(identifier, "lead")}
        })

      jobs = rewrite(identifier, "/cases/client-work")

      stored = Brando.Repo.get!(Case, holder.id)
      [linked, elsewhere] = stored.highlights

      assert linked.title == "Linked"
      assert linked.body =~ ~s(href="/cases/client-work")
      assert linked.body =~ "the work"
      assert elsewhere == Enum.at(holder.highlights, 1)
      assert stored.lead.title == "Lead"
      assert stored.lead.body =~ ~s(href="/cases/client-work")
      assert stored.title == "Holder"

      assert holder.id in Enum.map(jobs, & &1.args["entry_id"])
    end

    test "a has_many row gets the new address, and its case is rendered" do
      {_target, identifier} = insert_case(%{})
      {_other_target, other} = insert_case(%{slug: "other"})
      holder = Brando.Repo.insert!(%Case{title: "Holder", slug: "holder", type: :full_case})

      linked = Brando.Repo.insert!(%Chapter{case_id: holder.id, title: "Linked", body: linked_html(identifier)})
      elsewhere = Brando.Repo.insert!(%Chapter{case_id: holder.id, title: "Elsewhere", body: linked_html(other)})

      jobs = rewrite(identifier, "/cases/client-work")

      stored = Brando.Repo.get!(Chapter, linked.id)
      assert stored.title == "Linked"
      assert stored.body =~ ~s(href="/cases/client-work")
      assert Brando.Repo.get!(Chapter, elsewhere.id) == elsewhere

      assert holder.id in Enum.map(jobs, & &1.args["entry_id"])
    end

    test "rows stored without ids are rewritten too" do
      {_target, identifier} = insert_case(%{})
      holder = Brando.Repo.insert!(%Case{title: "Holder", slug: "holder", type: :full_case})

      # As a row written outside the form may be stored
      Brando.Repo.update_all(Ecto.Query.where(Case, id: ^holder.id),
        set: [
          highlights: [%Highlight{title: "Linked", body: linked_html(identifier)}, %Highlight{title: "Plain"}],
          lead: %Highlight{title: "Lead", body: linked_html(identifier)}
        ]
      )

      rewrite(identifier, "/cases/client-work")

      stored = Brando.Repo.get!(Case, holder.id)
      assert [%{title: "Linked", body: body}, %{title: "Plain", body: nil}] = stored.highlights
      assert body =~ ~s(href="/cases/client-work")
      assert stored.lead.body =~ ~s(href="/cases/client-work")
    end

    test "an embeds_one without a primary key and embeds whose relation raises on a replace" do
      {_target, identifier} = insert_case(%{})

      holder =
        Brando.Repo.insert!(%Case{
          title: "Holder",
          slug: "holder",
          type: :full_case,
          note: %Brando.LinkTest.Note{label: "Note", body: linked_html(identifier, "note")},
          aside: %Highlight{title: "Aside", body: linked_html(identifier, "aside")},
          archive: [
            %Highlight{title: "Archived", body: linked_html(identifier, "archived")},
            %Highlight{title: "Plain"}
          ]
        })

      jobs = rewrite(identifier, "/cases/client-work")

      stored = Brando.Repo.get!(Case, holder.id)
      assert stored.note.label == "Note"
      assert stored.note.body =~ ~s(href="/cases/client-work")
      assert stored.note.body =~ "note"
      assert stored.aside.id == holder.aside.id
      assert stored.aside.title == "Aside"
      assert stored.aside.body =~ ~s(href="/cases/client-work")
      assert [%{title: "Archived", body: body} = archived, plain] = stored.archive
      assert archived.id == hd(holder.archive).id
      assert body =~ ~s(href="/cases/client-work")
      assert plain == Enum.at(holder.archive, 1)

      assert holder.id in Enum.map(jobs, & &1.args["entry_id"])
    end

    test "an embeds_many the entry's query leaves out" do
      {_target, identifier} = insert_case(%{})

      holder =
        Brando.Repo.insert!(%Case{
          title: "Holder",
          slug: "holder",
          type: :full_case,
          extras: [%Highlight{title: "Extra", body: linked_html(identifier)}]
        })

      jobs = rewrite(identifier, "/cases/client-work")

      [extra] = Brando.Repo.one!(Ecto.Query.from(c in Case, where: c.id == ^holder.id, select: c.extras))
      assert extra.title == "Extra"
      assert extra.body =~ ~s(href="/cases/client-work")
      assert holder.id in Enum.map(jobs, & &1.args["entry_id"])
    end

    test "a has_many row detached before its rewrite is rewritten, and no case is rendered for it" do
      {_target, identifier} = insert_case(%{})
      holder = Brando.Repo.insert!(%Case{title: "Holder", slug: "holder", type: :full_case})
      chapter = Brando.Repo.insert!(%Chapter{case_id: holder.id, title: "Linked", body: linked_html(identifier)})

      # Another editor removes the row from its case (`on_replace: :nilify`)
      # after the scan found it, before the rewrite locks it
      test_pid = self()
      handler = "detach-chapter-after-scan"

      detach = fn _event, _measurements, %{source: source, query: query}, _config ->
        if self() == test_pid and source == "linktest_chapters" and not (query =~ "FOR UPDATE") do
          :telemetry.detach(handler)
          Brando.Repo.update_all(Ecto.Query.where(Chapter, id: ^chapter.id), set: [case_id: nil])
        end
      end

      :ok = :telemetry.attach(handler, BrandoIntegration.Repo.config()[:telemetry_prefix] ++ [:query], detach, nil)

      jobs =
        try do
          rewrite(identifier, "/cases/client-work")
        after
          :telemetry.detach(handler)
        end

      stored = Brando.Repo.get!(Chapter, chapter.id)
      assert stored.case_id == nil
      assert stored.body =~ ~s(href="/cases/client-work")
      refute holder.id in Enum.map(jobs, & &1.args["entry_id"])
    end

    test "an address the rich text refuses changes no row" do
      {_target, identifier} = insert_case(%{})

      holder =
        Brando.Repo.insert!(%Case{
          title: "Holder",
          slug: "holder",
          type: :full_case,
          highlights: [%Highlight{title: "Linked", body: linked_html(identifier)}]
        })

      chapter = Brando.Repo.insert!(%Chapter{case_id: holder.id, title: "Linked", body: linked_html(identifier)})

      assert rewrite(identifier, "javascript:alert(1)") == []
      assert Brando.Repo.get!(Case, holder.id).highlights == holder.highlights
      assert Brando.Repo.get!(Chapter, chapter.id) == chapter
    end
  end

  describe "stored links elsewhere follow the destination" do
    test "rich text in an html var, in a block or a table cell" do
      {target, identifier} = insert_case(%{})
      html = ~s(<p><a href="https://client.example/work" data-identifier-id="#{identifier.id}">the work</a></p>)

      block = Brando.Repo.insert!(%Brando.Content.Block{type: :module, uid: Brando.Utils.generate_uid()})
      row = Brando.Repo.insert!(%Brando.Content.TableRow{block_id: block.id})

      in_block = Brando.Repo.insert!(%Var{type: :rich_text, key: "body", block_id: block.id, value: html})
      in_cell = Brando.Repo.insert!(%Var{type: :rich_text, key: "cell", table_row_id: row.id, value: html})

      assert Brando.Content.Blocks.list_block_ids_with_identifier_in_html_vars(identifier.id) == [block.id]

      change_case(target, type: :full_case)

      assert Brando.Repo.get!(Var, in_block.id).value =~ ~s(href="/cases/client-work")
      assert Brando.Repo.get!(Var, in_cell.id).value =~ ~s(href="/cases/client-work")
    end

    test "a cached menu item" do
      {target, identifier} = insert_case(%{})
      user = Brando.Factory.insert(:random_user, role: :superuser)

      {:ok, _menu} =
        Brando.Navigation.create_menu(
          %{
            title: "Main",
            key: "link-others",
            language: "en",
            status: :published,
            items: [
              %{
                key: "case",
                status: :published,
                sequence: 0,
                link: %{type: :link, key: "link", label: "Link", link_type: :identifier, identifier_id: identifier.id}
              }
            ]
          },
          user
        )

      menu_url = fn ->
        {:ok, menu} = Brando.Navigation.get_menu("link-others", "en")
        menu.items |> hd() |> Brando.HTML.get_menu_item_url()
      end

      assert menu_url.() == "https://client.example/work"
      change_case(target, type: :full_case)
      assert menu_url.() == "/cases/client-work"
    end
  end

  describe "links to the entry" do
    test "a link var and a menu item go to the destination, then to the page" do
      {case_entry, identifier} = insert_case(%{})

      assert Brando.Villain.Filters.link_url(link_var(identifier), nil) == "https://client.example/work"
      assert Brando.HTML.get_menu_item_url(%{link: link_var(identifier)}) == "https://client.example/work"

      {_case_entry, identifier} = change_case(case_entry, type: :full_case)

      assert Brando.Villain.Filters.link_url(link_var(identifier), nil) == "/cases/client-work"
      assert Brando.HTML.get_menu_item_url(%{link: link_var(identifier)}) == "/cases/client-work"
    end

    test "the picker lists it where a URL is required" do
      {_case_entry, linked} = insert_case(%{})
      {_case_entry, nowhere} = insert_case(%{slug: "nowhere", external_link: nil})

      props = %{id: "picker", wanted_schemas: [Case], layout: :workspace, require_url: true}
      {:ok, socket} = SelectIdentifier.update(props, %Phoenix.LiveView.Socket{})

      assert Enum.map(socket.assigns.identifiers, & &1.id) == [linked.id]
      assert socket.assigns.schema_counts == %{Case => 1}

      {:noreply, socket} = SelectIdentifier.handle_event("select_identifier", %{"id" => to_string(nowhere.id)}, socket)
      assert socket.assigns.selected_identifier_id == nil
    end

    test "the picker marks it as external, with the host" do
      {_case_entry, identifier} = insert_case(%{external_link: "https://www.client.example/work"})

      html = render_component(&IdentifierRow.destination/1, identifier: identifier)
      assert html =~ "identifier-external"
      assert html =~ ~s(title="https://www.client.example/work")
      assert html =~ "client.example"
      refute html =~ ">https://www.client.example/work<"

      page = render_component(&IdentifierRow.destination/1, identifier: %Identifier{url: "/cases/a"})
      assert page =~ "/cases/a"
      refute page =~ "identifier-external"
    end
  end
end
