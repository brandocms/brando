defmodule Brando.TrashLinkTest.Description do
  @moduledoc false
  # A page's meta description drawn as rich text, so that a rewrite given
  # this module looks for links in it (IdentifierLinkRewriteTest). The
  # entry rendered is the page itself, `Brando.Pages.Page` on the same
  # table, which is in the trash.
  use Brando.Blueprint,
    application: "Brando",
    domain: "TrashLinkTest",
    schema: "Description",
    singular: "description",
    plural: "descriptions",
    gettext_module: Brando.Gettext

  table "pages"
  identifier false
  persist_identifier false

  attributes do
    attribute :meta_description, :text
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :meta_description, :rich_text
        end
      end
    end
  end
end

defmodule Brando.Content.IdentifierLinkRewriteTest do
  # Where a moved identifier's rich-text links are rewritten, and what one
  # failing schema leaves for the others. Synchronous: some tests make a
  # table refuse updates with a trigger, which the sandbox rolls back.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Blocks
  alias Brando.Content.Identifier
  alias Brando.LinkTest.Case
  alias Brando.LinkTest.Chapter
  alias Brando.Pages.Page
  alias Brando.SyncTest.Article
  alias Brando.SyncTest.ArticleItem
  alias Brando.SyncTest.ArticleQuote

  @old_url "https://client.example/work"
  @new_url "/cases/client-work"

  defp insert_case(attrs \\ %{}) do
    case_entry =
      %Case{title: "Client work", slug: "client-work", type: :external_link, external_link: "client.example/work"}
      |> struct(attrs)
      |> Brando.Repo.insert!()

    {:ok, identifier} = Brando.Content.create_identifier(Case, case_entry)
    {case_entry, identifier}
  end

  # An address change as a save makes it
  defp move(case_entry) do
    case_entry = case_entry |> Ecto.Changeset.change(type: :full_case) |> Brando.Repo.update!()
    {:ok, identifier} = Brando.Content.update_identifier(Case, case_entry)
    identifier
  end

  defp linked_html(identifier, url \\ @old_url),
    do: ~s(<p><a href="#{url}" data-identifier-id="#{identifier.id}">the work</a></p>)

  defp holder(attrs),
    do: Brando.Repo.insert!(struct(%Case{title: "Holder", slug: "holder", type: :full_case}, attrs))

  defp article(attrs), do: Brando.Repo.insert!(struct(%Article{title: "Article", slug: "article"}, attrs))

  defp rewrite(identifier, url \\ @new_url, modules \\ Blocks.identifier_link_modules()) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      Blocks.update_identifier_links_in_rich_text_fields(identifier.id, url, modules)
      all_enqueued(worker: Brando.Worker.EntryRenderer)
    end)
  end

  defp rendered(jobs, schema),
    do: for(%{args: %{"schema" => name, "entry_id" => id}} <- jobs, name == to_string(schema), do: id)

  # Postgres raises for every update of a row of `table` that matches `where`
  defp refuse_updates(table, where) do
    Brando.Repo.repo().query!("""
    CREATE OR REPLACE FUNCTION brando_test_refuse_update() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'refused by the test'; END $$
    """)

    Brando.Repo.repo().query!("""
    CREATE TRIGGER brando_test_refuse_update BEFORE UPDATE ON #{table}
    FOR EACH ROW WHEN (#{where}) EXECUTE FUNCTION brando_test_refuse_update()
    """)
  end

  # Postgres raises for the second update of a row of `table`, whichever row
  # that is. The count is kept in a sequence, which a rollback does not take
  # back: `update_attempts/0` reads it afterwards.
  defp refuse_second_update(table) do
    repo = Brando.Repo.repo()
    repo.query!("CREATE SEQUENCE brando_test_update_attempts")

    repo.query!("""
    CREATE OR REPLACE FUNCTION brando_test_refuse_second_update() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF nextval('brando_test_update_attempts') > 1 THEN RAISE EXCEPTION 'refused by the test'; END IF;
      RETURN NEW;
    END $$
    """)

    repo.query!("""
    CREATE TRIGGER brando_test_refuse_second_update BEFORE UPDATE ON #{table}
    FOR EACH ROW EXECUTE FUNCTION brando_test_refuse_second_update()
    """)
  end

  # Counts the updates of rows of `table`, for `update_attempts/0`
  defp count_updates(table) do
    repo = Brando.Repo.repo()
    repo.query!("CREATE SEQUENCE brando_test_update_attempts")

    repo.query!("""
    CREATE OR REPLACE FUNCTION brando_test_count_update() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN PERFORM nextval('brando_test_update_attempts'); RETURN NEW; END $$
    """)

    repo.query!("""
    CREATE TRIGGER brando_test_count_update BEFORE UPDATE ON #{table}
    FOR EACH ROW EXECUTE FUNCTION brando_test_count_update()
    """)
  end

  # Postgres raises for every render job queued for `schema`
  defp refuse_render_jobs(schema) do
    Brando.Repo.repo().query!("""
    CREATE OR REPLACE FUNCTION brando_test_refuse_job() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'refused by the test'; END $$
    """)

    Brando.Repo.repo().query!("""
    CREATE TRIGGER brando_test_refuse_job BEFORE INSERT ON oban_jobs
    FOR EACH ROW WHEN (NEW.args->>'schema' = '#{schema}') EXECUTE FUNCTION brando_test_refuse_job()
    """)
  end

  defp update_attempts do
    %{rows: [[attempts, called]]} =
      Brando.Repo.repo().query!("SELECT last_value, is_called FROM brando_test_update_attempts")

    if called, do: attempts, else: 0
  end

  # Stored as no embedded row can be loaded, with the text the scan looks
  # for: reading the column raises in Elixir, with no failed statement
  defp break_highlights(case_entry) do
    Brando.Repo.repo().query!(
      ~s(UPDATE linktest_cases SET highlights = '"data-identifier-id"'::jsonb WHERE id = $1),
      [case_entry.id]
    )
  end

  describe "rich text drawn only by a named form" do
    test "a top-level field, an embeds_many row and a has_many row get the new address" do
      {_target, identifier} = insert_case()

      # `subtitle` is a textarea in the default form and rich text in `form
      # :notes`; quotes and items are rich text only in other named forms
      entry =
        article(%{
          subtitle: linked_html(identifier),
          quotes: [%ArticleQuote{text: linked_html(identifier)}, %ArticleQuote{text: "Plain"}]
        })

      item = Brando.Repo.insert!(%ArticleItem{article_id: entry.id, label: "Item", link: linked_html(identifier)})

      jobs = rewrite(identifier)

      stored = Brando.Repo.get!(Article, entry.id)
      assert stored.subtitle =~ ~s(href="#{@new_url}")
      assert [%{text: quote_text}, %{text: "Plain"}] = stored.quotes
      assert quote_text =~ ~s(href="#{@new_url}")
      assert Brando.Repo.get!(ArticleItem, item.id).link =~ ~s(href="#{@new_url}")
      assert entry.id in rendered(jobs, Article)
    end

    test "a relation two forms draw is rewritten with the rich-text inputs of each" do
      fields = Blocks.subform_rich_text_fields_for(Article)

      assert [{:embed, :quotes, [:text]}] = for({:embed, :quotes, _} = quotes <- fields, do: quotes)
      assert [{:assoc, %{field: :items}, [:link]}] = for({:assoc, %{field: :items}, _} = items <- fields, do: items)
      assert :subtitle in Blocks.rich_text_fields_for(Article)
    end
  end

  describe "rich text in a schema without a stored identifier" do
    test "a row its own form draws gets the new address" do
      {_target, identifier} = insert_case()

      # No case: only the chapter's own form reaches it
      chapter = Brando.Repo.insert!(%Chapter{title: "Loose", body: linked_html(identifier)})

      jobs = rewrite(identifier)

      assert Brando.Repo.get!(Chapter, chapter.id).body =~ ~s(href="#{@new_url}")
      # Its context has no `get_chapter/1` to load it for a render
      assert rendered(jobs, Chapter) == []
    end

    test "subform rows in a table every site shares are not walked, nor written" do
      {_target, identifier} = insert_case()
      put_test_env(:shared_tables, [ArticleItem.__schema__(:source)])

      # Article's own table is a site's; the rows its `items` subform draws
      # would be read across every site
      entry = article(%{title: "Shared rows"})
      item = Brando.Repo.insert!(%ArticleItem{article_id: entry.id, label: "Item", link: linked_html(identifier)})

      refute List.keymember?(Blocks.rich_text_targets(Blocks.identifier_link_modules()), ArticleItem, 0)

      rewrite(identifier)

      assert Brando.Repo.get!(ArticleItem, item.id).link == linked_html(identifier)
    end

    test "embedded and shared schemas are not walked by themselves" do
      modules = Blocks.identifier_link_modules()

      assert Chapter in modules
      refute Brando.LinkTest.Highlight in modules
      refute Brando.Users.User in modules
    end
  end

  describe "a column found through two modules" do
    test "renders the row's parent, whichever module comes first" do
      for modules <- [[Case, Chapter], [Chapter, Case]] do
        {_target, identifier} = insert_case(%{slug: "client-work-#{inspect(modules)}"})
        parent = holder(%{slug: "holder-#{inspect(modules)}"})
        chapter = Brando.Repo.insert!(%Chapter{case_id: parent.id, title: "Linked", body: linked_html(identifier)})

        jobs = rewrite(identifier, @new_url, modules)

        assert Brando.Repo.get!(Chapter, chapter.id).body =~ ~s(href="#{@new_url}")
        assert parent.id in rendered(jobs, Case), "the parent, for #{inspect(modules)}"
      end
    end
  end

  describe "two Blueprints on one table" do
    test "both render the row, which is written once, whichever comes first" do
      note = Brando.RichTextDefaultFormTest.Note
      count_updates(Article.__schema__(:source))

      for {modules, n} <- Enum.with_index([[note, Article], [Article, note]], 1) do
        {_target, identifier} = insert_case(%{slug: "client-work-#{n}"})
        entry = article(%{slug: "article-#{n}", subtitle: linked_html(identifier)})

        jobs = rewrite(identifier, @new_url, modules)

        assert Brando.Repo.get!(Article, entry.id).subtitle =~ ~s(href="#{@new_url}")
        assert update_attempts() == n, "one write, for #{inspect(modules)}"
        assert entry.id in rendered(jobs, Article), "Article, for #{inspect(modules)}"
        assert entry.id in rendered(jobs, note), "Note, for #{inspect(modules)}"
      end
    end
  end

  describe "a row without a link to the moved entry" do
    test "is not written, and not rendered" do
      {_target, identifier} = insert_case()
      {_other_target, other} = insert_case(%{slug: "other"})

      # A column the default form draws as plain text and `form :notes` as
      # rich text, linking to another entry
      entry = article(%{subtitle: linked_html(other)})
      old = ~N[2020-01-01 00:00:00]
      Brando.Repo.update_all(Ecto.Query.where(Article, id: ^entry.id), set: [updated_at: old])

      jobs = rewrite(identifier)

      stored = Brando.Repo.get!(Article, entry.id)
      assert stored.subtitle == linked_html(other)
      assert stored.updated_at == old
      assert rendered(jobs, Article) == []
    end
  end

  describe "one schema failing" do
    test "an Elixir exception in one schema leaves the others rewritten, and is logged" do
      {target, identifier} = insert_case()
      summary_holder = holder(%{summary: linked_html(identifier)})
      break_highlights(holder(%{slug: "broken"}))
      chapter = Brando.Repo.insert!(%Chapter{title: "Loose", body: linked_html(identifier)})
      entry = article(%{subtitle: linked_html(identifier)})

      log = Brando.Test.OwnLog.capture(fn -> move(target) end)

      assert log =~ "Brando.LinkTest.Case"
      assert log =~ "keep their old address"
      # The case's step failed whole: its rows keep the old address
      assert Brando.Repo.get!(Case, summary_holder.id).summary == linked_html(identifier)
      assert Brando.Repo.get!(Chapter, chapter.id).body =~ ~s(href="#{@new_url}")
      assert Brando.Repo.get!(Article, entry.id).subtitle =~ ~s(href="#{@new_url}")
    end

    test "a failed statement in one schema leaves the others rewritten, and is logged" do
      {target, identifier} = insert_case()
      summary_holder = holder(%{summary: linked_html(identifier)})
      chapter = Brando.Repo.insert!(%Chapter{title: "Loose", body: linked_html(identifier)})
      entry = article(%{subtitle: linked_html(identifier)})
      refuse_updates("linktest_chapters", "true")

      log = Brando.Test.OwnLog.capture(fn -> move(target) end)

      assert log =~ "Brando.LinkTest.Chapter"
      assert log =~ "refused by the test"
      assert Brando.Repo.get!(Case, summary_holder.id).summary =~ ~s(href="#{@new_url}")
      assert Brando.Repo.get!(Chapter, chapter.id).body == linked_html(identifier)
      assert Brando.Repo.get!(Article, entry.id).subtitle =~ ~s(href="#{@new_url}")
    end

    test "a failing ref step leaves the vars and form fields rewritten" do
      {target, identifier} = insert_case()
      block = Brando.Repo.insert!(%Brando.Content.Block{type: :module, uid: Brando.Utils.generate_uid()})

      ref =
        Brando.Repo.insert!(%Brando.Content.Ref{
          block_id: block.id,
          name: "text",
          uid: Brando.Utils.generate_uid(),
          data: %Brando.Villain.Blocks.TextBlock{
            type: "text",
            data: %Brando.Villain.Blocks.TextBlock.Data{text: linked_html(identifier)}
          }
        })

      var =
        Brando.Repo.insert!(%Brando.Content.Var{
          type: :rich_text,
          key: "body",
          block_id: block.id,
          value: linked_html(identifier)
        })

      summary_holder = holder(%{summary: linked_html(identifier)})
      refuse_updates("content_refs", "true")

      log = Brando.Test.OwnLog.capture(fn -> move(target) end)

      assert log =~ "block refs"
      assert log =~ "refused by the test"
      assert Brando.Repo.get!(Brando.Content.Ref, ref.id).data.data.text == linked_html(identifier)
      assert Brando.Repo.get!(Brando.Content.Var, var.id).value =~ ~s(href="#{@new_url}")
      assert Brando.Repo.get!(Case, summary_holder.id).summary =~ ~s(href="#{@new_url}")
    end
  end

  describe "one schema failing inside a revision restore" do
    # The restore saves the page and its identifier in one transaction, and
    # rewrites the links to the page inside it
    setup do
      user = Brando.Factory.insert(:random_user)

      {:ok, page} =
        Brando.Pages.create_page(Brando.Factory.params_for(:page, vars: [], uri: "kulturkalender"), user)

      {:ok, revision} = Brando.Revisions.create_revision(page, user, false)
      {:ok, _} = Brando.Pages.update_page(page.id, %{uri: "ny-adresse"}, user)
      {:ok, identifier} = Brando.Content.get_identifier(Page, page)

      %{user: user, page: page, revision: revision, identifier: identifier, url: Identifier.link_url(identifier)}
    end

    defp restore(c) do
      Oban.Testing.with_testing_mode(:manual, fn ->
        log =
          Brando.Test.OwnLog.capture(fn ->
            assert {:ok, _} = Brando.Revisions.set_entry_to_revision(Page, c.page.id, c.revision.revision, c.user)
          end)

        {log, all_enqueued(worker: Brando.Worker.EntryRenderer)}
      end)
    end

    defp restored_url(c) do
      {:ok, identifier} = Brando.Content.get_identifier(Page, c.page)
      refute Identifier.link_url(identifier) == c.url
      Identifier.link_url(identifier)
    end

    test "a failed statement after a row was rewritten takes back that schema only", c do
      summary_holder = holder(%{summary: linked_html(c.identifier, c.url)})
      parent = holder(%{slug: "parent"})

      [first, second] =
        for n <- 1..2,
            do: Brando.Repo.insert!(%Chapter{case_id: parent.id, title: "#{n}", body: linked_html(c.identifier, c.url)})

      entry = article(%{subtitle: linked_html(c.identifier, c.url)})
      refuse_second_update("linktest_chapters")

      {log, jobs} = restore(c)
      url = restored_url(c)

      assert log =~ "Brando.LinkTest.Chapter"
      assert log =~ "refused by the test"
      assert Brando.Repo.get!(Page, c.page.id).uri == "kulturkalender"
      assert {:ok, {%{revision: active}, _}} = Brando.Revisions.get_active_revision(Page, c.page.id)
      assert active == c.revision.revision

      assert Brando.Repo.get!(Case, summary_holder.id).summary =~ ~s(href="#{url}")
      assert summary_holder.id in rendered(jobs, Case)

      # One chapter was rewritten before the other refused, in either order
      assert update_attempts() == 2
      assert Brando.Repo.get!(Chapter, first.id).body == linked_html(c.identifier, c.url)
      assert Brando.Repo.get!(Chapter, second.id).body == linked_html(c.identifier, c.url)
      assert rendered(jobs, Chapter) == []
      refute parent.id in rendered(jobs, Case)

      assert Brando.Repo.get!(Article, entry.id).subtitle =~ ~s(href="#{url}")
      assert entry.id in rendered(jobs, Article)
    end

    test "an Elixir exception in one schema leaves the restore and the others", c do
      summary_holder = holder(%{summary: linked_html(c.identifier, c.url)})
      break_highlights(holder(%{slug: "broken"}))
      chapter = Brando.Repo.insert!(%Chapter{title: "Loose", body: linked_html(c.identifier, c.url)})
      entry = article(%{subtitle: linked_html(c.identifier, c.url)})

      {log, jobs} = restore(c)
      url = restored_url(c)

      assert log =~ "Brando.LinkTest.Case"
      assert Brando.Repo.get!(Page, c.page.id).uri == "kulturkalender"
      assert Brando.Repo.get!(Case, summary_holder.id).summary == linked_html(c.identifier, c.url)
      refute summary_holder.id in rendered(jobs, Case)
      assert Brando.Repo.get!(Chapter, chapter.id).body =~ ~s(href="#{url}")
      assert Brando.Repo.get!(Article, entry.id).subtitle =~ ~s(href="#{url}")
      assert entry.id in rendered(jobs, Article)
    end
  end

  describe "open forms" do
    # A process that forwards what the entry's open forms hear, as `heard`
    defp listen(schema, id, heard \\ nil) do
      test = self()
      topic = Brando.Tenant.Topic.entry("field_sync", schema, id)

      spawn_link(fn ->
        Phoenix.PubSub.subscribe(Brando.pubsub(), topic)
        send(test, {:listening, topic})
        forward(test, heard || {schema, id})
      end)

      assert_receive {:listening, ^topic}
    end

    defp forward(test, entry) do
      receive do
        message -> send(test, {:heard, entry, message})
      end

      forward(test, entry)
    end

    test "on each entry whose rows are rewritten hear of it as of a save by no editor" do
      {target, identifier} = insert_case()
      entry = article(%{subtitle: linked_html(identifier)})
      quoted = article(%{slug: "quoted", quotes: [%ArticleQuote{text: linked_html(identifier)}]})
      other = article(%{slug: "other", subtitle: "<p>No link</p>"})
      parent = holder(%{slug: "parent"})
      Brando.Repo.insert!(%Chapter{case_id: parent.id, title: "Linked", body: linked_html(identifier)})

      for {schema, id} <- [{Article, entry.id}, {Article, quoted.id}, {Article, other.id}, {Case, parent.id}],
          do: listen(schema, id)

      move(target)

      for heard <- [{Article, entry.id}, {Article, quoted.id}, {Case, parent.id}],
          do: assert_receive({:heard, ^heard, {:entry_saved, %{tab: nil, user_id: nil}}})

      refute_receive {:heard, {Article, _id}, _message}
    end

    test "hear of it once the transaction around the rewrite has committed" do
      {_target, identifier} = insert_case()
      entry = article(%{subtitle: linked_html(identifier)})
      listen(Article, entry.id)

      {:ok, _jobs} =
        Brando.Repo.transaction(fn ->
          jobs = rewrite(identifier)
          refute_receive {:heard, _entry, _message}
          jobs
        end)

      assert_receive {:heard, {Article, _id}, {:entry_saved, %{tab: nil}}}
    end

    test "hear nothing of a rewrite rolled back" do
      {_target, identifier} = insert_case()
      entry = article(%{subtitle: linked_html(identifier)})
      listen(Article, entry.id)

      {:error, :rolled_back} =
        Brando.Repo.transaction(fn ->
          rewrite(identifier)
          Brando.Repo.rollback(:rolled_back)
        end)

      refute_receive {:heard, _entry, _message}
    end

    test "hear nothing of a schema's step rolled back in the transaction around the rewrite" do
      {_target, identifier} = insert_case()
      parent = holder(%{slug: "parent"})
      chapter = Brando.Repo.insert!(%Chapter{case_id: parent.id, title: "Linked", body: linked_html(identifier)})
      entry = article(%{subtitle: linked_html(identifier)})
      # The chapter's step cannot queue its parent's render, and is rolled
      # back to its savepoint; the transaction goes on
      refuse_render_jobs(Case)
      listen(Case, parent.id)
      listen(Article, entry.id)

      log =
        Brando.Test.OwnLog.capture(fn ->
          assert {:ok, _jobs} = Brando.Repo.transaction(fn -> rewrite(identifier) end)
        end)

      assert log =~ "refused by the test"
      assert Brando.Repo.get!(Chapter, chapter.id).body == linked_html(identifier)
      assert Brando.Repo.get!(Article, entry.id).subtitle =~ ~s(href="#{@new_url}")
      assert_receive {:heard, {Article, _id}, {:entry_saved, %{tab: nil}}}
      refute_receive {:heard, {Case, _id}, _message}
    end
  end

  describe "open forms in another environment" do
    # Two environments, each with its own copy of the pages table and of a
    # page made before them
    setup do
      user = Brando.Factory.insert(:random_user)
      {:ok, page} = Brando.Pages.create_page(Brando.Factory.params_for(:page, uri: "linked"), user)
      put_test_env(:tenancy_mode, :single)

      prefixes = %{
        production: Brando.Tenant.prefix("acme", "production"),
        staging: Brando.Tenant.prefix("acme", "staging")
      }

      for prefix <- Map.values(prefixes) do
        Brando.Repo.repo().query!(~s(CREATE SCHEMA "#{prefix}"))
        Brando.Repo.repo().query!(~s[CREATE TABLE "#{prefix}".pages (LIKE public.pages INCLUDING ALL)])
      end

      Map.put(prefixes, :page, page)
    end

    test "hear of a rewrite in their environment, made in a transaction begun in another", c do
      {_target, identifier} = insert_case()
      page = c.page

      # Each environment holds a page with this id, linking to the moved entry
      for prefix <- [c.production, c.staging] do
        Brando.Repo.repo().query!(~s(INSERT INTO "#{prefix}".pages SELECT * FROM public.pages WHERE id = $1), [page.id])

        Brando.Repo.repo().query!(~s(UPDATE "#{prefix}".pages SET meta_description = $1 WHERE id = $2), [
          linked_html(identifier),
          page.id
        ])
      end

      Brando.Tenant.with_prefix(c.production, fn -> listen(Page, page.id, :production) end)
      Brando.Tenant.with_prefix(c.staging, fn -> listen(Page, page.id, :staging) end)

      Brando.Tenant.with_prefix(c.production, fn ->
        {:ok, _jobs} =
          Brando.Repo.transaction(fn ->
            Brando.Tenant.with_prefix(c.staging, fn ->
              rewrite(identifier, @new_url, [Brando.TrashLinkTest.Description, Page])
            end)
          end)
      end)

      in_staging = Brando.Tenant.with_prefix(c.staging, fn -> Brando.Repo.get!(Page, page.id) end)
      assert in_staging.meta_description == linked_html(identifier, @new_url)
      assert_receive {:heard, :staging, {:entry_saved, %{tab: nil}}}
      refute_receive {:heard, :production, _message}
    end
  end

  describe "an entry in the trash" do
    # Rewritten and rendered like any other: a restore does not render it,
    # so the render now is what brings it back with the new address
    test "has its links rewritten and its HTML rendered, and is restored with the new address" do
      {_target, identifier} = insert_case()
      user = Brando.Factory.insert(:random_user, role: :superuser)
      module = Brando.ProposalFixtures.module!(user, "Description", "<div>{{ entry.meta_description }}</div>", [])
      page = Brando.ProposalFixtures.page!(user, "Trashed", module)
      trashed_at = DateTime.truncate(DateTime.utc_now(), :second)

      Brando.Repo.update_all(from(p in Page, where: p.id == ^page.id),
        set: [meta_description: linked_html(identifier), deleted_at: trashed_at]
      )

      jobs = rewrite(identifier, @new_url, [Brando.TrashLinkTest.Description, Page])

      assert Brando.Repo.get!(Page, page.id).meta_description == linked_html(identifier, @new_url)
      assert [job] = for(job <- jobs, job.args["schema"] == to_string(Page), do: job)
      assert job.args["entry_id"] == page.id

      assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
      html = Brando.Repo.get!(Page, page.id).rendered_blocks
      assert html =~ @new_url
      refute html =~ @old_url

      assert {:ok, restored} = Brando.Authorization.Boundary.restore(user, Brando.Repo.get!(Page, page.id))
      assert restored.deleted_at == nil
      assert restored.meta_description == linked_html(identifier, @new_url)
      assert restored.rendered_blocks == html
    end
  end
end
