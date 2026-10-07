defmodule Brando.NotesTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query
  import Swoosh.TestAssertions

  alias Brando.Activity.Event
  alias Brando.Factory
  alias Brando.Notes
  alias Brando.Notes.Mention
  alias Brando.Notes.Note
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Ecto.Changeset

  setup do
    author = Factory.insert(:random_user, name: "Ingrid Hauge")
    other = Factory.insert(:random_user, name: "Trond Mjøen", language: "no")
    page = Factory.insert(:page, creator: author)
    {:ok, author: author, other: other, page: page}
  end

  defp thread!(page, user, attrs) do
    {:ok, note, mentioned} = Notes.create_thread(Page, page.id, user, attrs)
    {note, mentioned}
  end

  defp events(page, actions) do
    Repo.all(
      from(e in Event,
        where: e.schema == ^to_string(Page) and e.entry_id == ^page.id and e.action in ^actions,
        order_by: [asc: e.id]
      )
    )
  end

  defp insert_block(page, user, uid, html) do
    %Page.Blocks{}
    |> Changeset.change(%{entry_id: page.id, sequence: 0})
    |> Changeset.put_assoc(:block, %{
      uid: uid,
      type: :module,
      active: true,
      source: "Elixir.Brando.Pages.Page.Blocks",
      creator_id: user.id,
      sequence: 0,
      vars: [%{type: :html, key: "body", label: "Body", value: html, sequence: 0}],
      refs: [],
      children: []
    })
    |> Repo.insert!()
  end

  defp set_html(uid, html) do
    block_id = Repo.one!(from(b in "content_blocks", where: b.uid == ^uid, select: b.id))
    Repo.update_all(from(v in "content_vars", where: v.block_id == ^block_id), set: [value: html])
  end

  describe "threads" do
    test "a note on the entry, a reply and the thread's order", %{author: author, other: other, page: page} do
      {note, []} = thread!(page, author, %{"body" => "  Check the room count  "})
      assert note.body == "Check the room count"
      assert note.author_id == author.id
      assert is_nil(note.block_uid)

      {:ok, reply, []} = Notes.reply(note, other, %{"body" => "Done"})
      assert reply.parent_id == note.id

      assert [thread] = Notes.list_threads(Page, page.id)
      assert thread.id == note.id
      assert Enum.map(thread.replies, & &1.body) == ["Done"]
      assert thread.author.name == "Ingrid Hauge"
      assert Notes.count_open(Page, page.id) == 1
    end

    test "anchors to a block, a field and a text range", %{author: author, page: page} do
      {block, _} = thread!(page, author, %{"body" => "Room count", "block_uid" => "B1", "anchor_label" => "Facts"})
      {field, _} = thread!(page, author, %{"body" => "Too long", "field_path" => "meta_description"})

      {text, _} =
        thread!(page, author, %{
          "body" => "Chimneys?",
          "block_uid" => "B1",
          "field_path" => "var:12",
          "range" => %{"quote" => "ventilation towers"}
        })

      assert {block.block_uid, block.field_path} == {"B1", nil}
      assert {field.block_uid, field.field_path} == {nil, "meta_description"}
      assert text.range == %{"quote" => "ventilation towers"}
    end

    test "a note needs words", %{author: author, page: page} do
      assert {:error, %Changeset{errors: [body: _]}} = Notes.create_thread(Page, page.id, author, %{"body" => "  "})
    end

    test "resolving and reopening, and a reply reopens a resolved thread", %{author: author, other: other, page: page} do
      {note, _} = thread!(page, author, %{"body" => "Photo credit?"})

      {:ok, resolved} = Notes.resolve(note, other)
      assert resolved.resolved_by_id == other.id
      assert Note.resolved?(resolved)
      assert Notes.count_open(Page, page.id) == 0
      assert {:ok, ^resolved} = Notes.resolve(resolved, other)

      {:ok, reopened} = Notes.reopen(resolved, author)
      refute Note.resolved?(reopened)
      assert is_nil(reopened.resolved_by_id)

      {:ok, resolved} = Notes.resolve(reopened, author)
      {:ok, _reply, _} = Notes.reply(resolved, other, %{"body" => "One more thing"})
      refute Note.resolved?(Repo.get!(Note, note.id))
    end

    test "replies only go to threads", %{author: author, page: page} do
      {note, _} = thread!(page, author, %{"body" => "Hi"})
      {:ok, reply, _} = Notes.reply(note, author, %{"body" => "Me again"})
      assert {:error, :not_a_thread} = Notes.reply(reply, author, %{"body" => "x"})
      assert {:error, :not_a_thread} = Notes.resolve(reply, author)
    end

    test "adding, resolving and reopening are in the entry's activity", %{author: author, page: page} do
      {note, _} = thread!(page, author, %{"body" => "Is this right?", "anchor_label" => "Text · Intro"})
      {:ok, note} = Notes.resolve(note, author)
      {:ok, _} = Notes.reopen(note, author)

      assert [added, resolved, reopened] = events(page, [:note_added, :note_resolved, :note_reopened])
      assert added.action == :note_added
      assert added.user_id == author.id
      assert added.details == %{"note" => note.id, "excerpt" => "Is this right?", "anchor" => "Text · Intro"}
      assert resolved.action == :note_resolved
      assert reopened.action == :note_reopened
    end

    test "changes are broadcast to everyone with the entry open", %{author: author, page: page} do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Notes.topic(Page, page.id))
      {note, _} = thread!(page, author, %{"body" => "Hello"})
      assert_receive {:notes_changed, %{event: :added, note_id: note_id, entry_id: entry_id}}
      assert {note_id, entry_id} == {note.id, page.id}

      {:ok, _} = Notes.resolve(note, author)
      assert_receive {:notes_changed, %{event: :resolved}}
    end
  end

  describe "mentions" do
    test "@Name becomes a token for users who can read the entry", %{author: author, other: other, page: page} do
      {note, mentioned} =
        thread!(page, author, %{
          "body" => "@Trond Mjøen can you check with the client? @Nobody",
          "mentions" => [to_string(other.id), "999999"]
        })

      assert note.body == "<@#{other.id}> can you check with the client? @Nobody"
      assert Enum.map(mentioned, & &1.id) == [other.id]
      assert Notes.mentioned_ids(note.body) == [other.id]
      assert Notes.segments(note.body) == [{:mention, other.id}, {:text, " can you check with the client? @Nobody"}]
      assert Notes.plain_text(note.body, %{other.id => "Trond Mjøen"}) =~ "@Trond Mjøen can you check"

      assert [%Mention{note: %Note{id: note_id}}] = Notes.mentions_for(other.id)
      assert note_id == note.id
    end

    test "a mention the body no longer names, or of yourself, is not kept", %{author: author, other: other, page: page} do
      {note, mentioned} =
        thread!(page, author, %{"body" => "No names here, @Ingrid Hauge", "mentions" => [other.id, author.id]})

      assert Enum.map(mentioned, & &1.id) == [author.id]
      assert note.body == "No names here, <@#{author.id}>"
      assert Notes.mentions_for(other.id) == []
      assert Notes.mentions_for(author.id) == []
    end

    test "the longest name wins", %{author: author, page: page} do
      ann = %{id: 1, name: "Ann"}
      anna = %{id: 2, name: "Anna"}
      assert {"<@2> and <@1>", [_, _]} = Notes.encode_mentions("@Anna and @Ann", [ann, anna])
      _ = {author, page}
    end

    test "one email per user every ten minutes, collecting the mentions between", %{
      author: author,
      other: other,
      page: page
    } do
      {first, _} = thread!(page, author, %{"body" => "@Trond Mjøen first", "mentions" => [other.id]})

      assert_email_sent(fn email ->
        assert email.to == [{"", other.email}]
        assert email.subject =~ "Ingrid Hauge"
        assert email.text_body =~ "@Trond Mjøen first"
      end)

      # Within ten minutes: the job snoozes, nothing is sent.
      {:ok, _, _} = Notes.reply(first, author, %{"body" => "@Trond Mjøen second", "mentions" => [other.id]})
      {:ok, _, _} = Notes.reply(first, author, %{"body" => "@Trond Mjøen third", "mentions" => [other.id]})
      assert_no_email_sent()
      assert {:snooze, seconds} = Notes.deliver_mentions(other.id)
      assert seconds in 590..600

      # Ten minutes later, one email with both.
      later = DateTime.add(DateTime.utc_now(), 601, :second)
      assert :ok = Notes.deliver_mentions(other.id, later)

      assert_email_sent(fn email ->
        assert email.text_body =~ "second"
        assert email.text_body =~ "third"
        assert email.text_body =~ ~r/second.*third/s
        not (email.text_body =~ "first")
      end)

      assert Repo.aggregate(from(m in Mention, where: m.user_id == ^other.id and is_nil(m.emailed_at)), :count) == 0
      assert :ok = Notes.deliver_mentions(other.id, DateTime.add(later, 700, :second))
      assert_no_email_sent()
    end

    test "the email is in the recipient's language", %{author: author, other: other, page: page} do
      thread!(page, author, %{"body" => "@Trond Mjøen hei", "mentions" => [other.id]})
      assert_email_sent(fn email -> assert email.subject =~ "nevnte deg" end)
    end
  end

  describe "permissions" do
    test "only someone who may update the entry can write notes", %{page: page} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      superuser = Factory.insert(:random_user, role: :superuser)
      {:ok, _} = Brando.Authorization.Migration.run()
      stranger = Factory.insert(:random_user)

      assert Notes.can_write?(superuser, page)
      refute Notes.can_write?(stranger, page)
      assert {:error, :forbidden} = Notes.create_thread(Page, page.id, stranger, %{"body" => "Hi"})

      {note, _} = thread!(page, superuser, %{"body" => "Hi"})
      assert {:error, :forbidden} = Notes.resolve(note, stranger)
      assert {:error, :forbidden} = Notes.reply(note, stranger, %{"body" => "x"})

      refute stranger.id in Enum.map(Notes.mentionable_users(page), & &1.id)
      assert superuser.id in Enum.map(Notes.mentionable_users(page), & &1.id)
    end
  end

  describe "lifecycle" do
    test "trashing the entry soft-deletes its notes and restoring brings them back", %{author: author, page: page} do
      {note, _} = thread!(page, author, %{"body" => "Keep me"})
      {earlier, _} = thread!(page, author, %{"body" => "Gone before"})
      Repo.update_all(from(n in Note, where: n.id == ^earlier.id), set: [deleted_at: DateTime.utc_now()])

      {:ok, trashed} = Pages.delete_page(page.id, author)
      assert Notes.list_threads(Page, page.id) == []
      assert Repo.get!(Note, note.id).deleted_at

      {:ok, _} = Brando.Authorization.Boundary.restore(author, trashed)
      assert [%{id: id}] = Notes.list_threads(Page, page.id)
      assert id == note.id
    end

    test "handing a user's content to someone else leaves their notes and mentions theirs", %{
      author: author,
      other: other,
      page: page
    } do
      {note, _} = thread!(page, author, %{"body" => "@Trond Mjøen look", "mentions" => [other.id]})
      third = Factory.insert(:random_user)

      tables = Enum.map(Brando.Users.get_user_content_summary(author.id), & &1.table)
      refute "entry_notes" in tables
      {:ok, _} = Brando.Users.transfer_user_content(author.id, third.id)
      {:ok, _} = Brando.Users.transfer_user_content(other.id, third.id)

      assert Repo.get!(Note, note.id).author_id == author.id
      assert [_] = Notes.mentions_for(other.id)
    end

    test "a site without the notes table can still save, trash and restore entries", %{page: page} do
      put_test_env(:tenancy_mode, :multi)
      Repo.query!(~s(CREATE SCHEMA "tenant_notes_unmigrated"))

      assert {:ok, :still_working} =
               Repo.transaction(fn ->
                 Brando.Tenant.with_prefix("tenant_notes_unmigrated", fn ->
                   assert :ok = Notes.entry_saved(Page, page)
                   assert :ok = Notes.entry_deleted(Page, %{page | deleted_at: DateTime.utc_now()}, true)
                   assert :ok = Notes.entry_restored(Page, %{page | deleted_at: DateTime.utc_now()})
                   assert :ok = Notes.entries_purged(Page, [page.id])
                 end)

                 Repo.one!(from(p in Page, where: p.id == ^page.id, select: count()), prefix: "public")
                 :still_working
               end)
    end

    test "purging entries removes their notes", %{author: author, page: page} do
      {note, _} = thread!(page, author, %{"body" => "Bye"})
      Notes.entries_purged(Page, [page.id])
      refute Repo.get(Note, note.id)
    end

    test "a note on a deleted block is detached, not deleted, and comes back with the block", %{
      author: author,
      page: page
    } do
      insert_block(page, author, "blockA", "<p>Hello</p>")
      {note, _} = thread!(page, author, %{"body" => "On A", "block_uid" => "blockA"})
      {other, _} = thread!(page, author, %{"body" => "On missing", "block_uid" => "blockZ"})
      Phoenix.PubSub.subscribe(Brando.pubsub(), Notes.topic(Page, page.id))

      assert :ok = Notes.entry_saved(Page, page)
      assert is_nil(Repo.get!(Note, note.id).detached_at)
      assert Repo.get!(Note, other.id).detached_at
      assert_receive {:notes_changed, %{event: :anchors}}

      Repo.delete_all(from(eb in Page.Blocks, where: eb.entry_id == ^page.id))
      Repo.delete_all(from(b in "content_blocks", where: b.uid == "blockA"))
      :ok = Notes.entry_saved(Page, page)
      assert %Note{detached_at: %DateTime{}, deleted_at: nil} = Repo.get!(Note, note.id)
      assert [_, _] = Notes.list_threads(Page, page.id)

      insert_block(page, author, "blockA", "<p>Hello</p>")
      :ok = Notes.entry_saved(Page, page)
      assert is_nil(Repo.get!(Note, note.id).detached_at)
    end

    test "a note whose marked text is deleted becomes a note on its block, marked text removed", %{
      author: author,
      page: page
    } do
      insert_block(page, author, "blockT", "<p>Placeholder</p>")

      {note, _} =
        thread!(page, author, %{"body" => "Chimneys?", "block_uid" => "blockT", "range" => %{"quote" => "towers"}})

      set_html("blockT", ~s(<p>the original <span data-brando-note="#{note.id}">towers</span> remain</p>))
      :ok = Notes.entry_saved(Page, page)
      assert is_nil(Repo.get!(Note, note.id).text_removed_at)

      set_html("blockT", "<p>the original remain</p>")
      :ok = Notes.entry_saved(Page, page)
      removed = Repo.get!(Note, note.id)
      assert removed.text_removed_at
      assert removed.block_uid == "blockT"
      assert is_nil(removed.detached_at)

      set_html("blockT", ~s(<p><span data-brando-note="#{note.id}">towers</span></p>))
      :ok = Notes.entry_saved(Page, page)
      assert is_nil(Repo.get!(Note, note.id).text_removed_at)
    end

    test "notes are kept in each site's own schema", %{author: author, page: page} do
      put_test_env(:tenancy_mode, :multi)
      prefix = "tenant_notes_production"
      Repo.query!(~s(CREATE SCHEMA "#{prefix}"))

      for table <- ~w(pages images entry_notes note_mentions activity_events) do
        Repo.query!(~s{CREATE TABLE "#{prefix}".#{table} (LIKE public.#{table} INCLUDING ALL)})
      end

      {public_note, _} = thread!(page, author, %{"body" => "Public"})

      Brando.Tenant.with_prefix(prefix, fn ->
        Repo.query!(~s{INSERT INTO "#{prefix}".pages SELECT * FROM public.pages WHERE id = $1}, [page.id])
        assert Notes.list_threads(Page, page.id) == []
        {tenant_note, _} = thread!(page, author, %{"body" => "Tenant"})
        assert [%{body: "Tenant"}] = Notes.list_threads(Page, page.id)
        assert tenant_note.id
      end)

      assert [%{id: id, body: "Public"}] = Notes.list_threads(Page, page.id)
      assert id == public_note.id
    end
  end

  describe "marks" do
    test "strip_marks keeps the text and every other span" do
      html =
        ~s(<p>A <span data-brando-note="4">kept <span class="lead">the <span data-brando-note="9">tiled</span></span> pools</span>.</p><span class="x">y</span>)

      assert Notes.strip_marks(html) ==
               ~s(<p>A kept <span class="lead">the tiled</span> pools.</p><span class="x">y</span>)

      assert Notes.strip_marks("<p>none</p>") == "<p>none</p>"
      assert Notes.mark_ids(~s(<span data-brando-note=\\"12\\">x</span>)) == [12]
    end

    test "the final render pass removes them" do
      html = ~s(<p>The <span data-brando-note="3">restoration</span> kept the pools.</p>)

      assert Brando.Villain.parse_and_render(html, Brando.Villain.get_base_context()) ==
               "<p>The restoration kept the pools.</p>"
    end

    test "rendered blocks never carry them, on the site or in the live preview", %{author: author} do
      {:ok, module} =
        :module
        |> Factory.params_for(%{
          code: "<div>{% ref refs.body %}|{{ intro }}</div>",
          name: "Notes module",
          refs: [
            %{
              name: "body",
              description: nil,
              uid: Brando.Utils.generate_uid(),
              data: %{type: "text", data: %{text: "", type: "paragraph"}}
            }
          ]
        })
        |> Brando.Content.create_module(author)

      block = %{
        block: %{
          type: :module,
          source: "Elixir.Brando.Pages.Page.Blocks",
          module_id: module.id,
          uid: Brando.Utils.generate_uid(),
          refs: [
            %{
              name: "body",
              description: nil,
              uid: Brando.Utils.generate_uid(),
              data: %{
                type: "text",
                data: %{text: ~s(<p>The <span data-brando-note="3">tiled pools</span></p>), type: "paragraph"}
              }
            }
          ],
          vars: [
            %{key: "intro", label: "Intro", type: :html, value: ~s(<span data-brando-note="4">Intro</span> text)}
          ]
        }
      }

      parsed = Brando.Villain.parse([block], %Page{})
      assert parsed =~ "tiled pools"
      assert parsed =~ "Intro text"
      # The live preview renders through the same parse.
      refute parsed =~ "data-brando-note"
    end
  end
end
