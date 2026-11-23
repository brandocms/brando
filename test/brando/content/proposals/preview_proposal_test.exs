defmodule Brando.Content.Proposals.PreviewProposalTest do
  # `preview_proposal`: a connected tool's short-lived public link to a page
  # of its own proposal, before the person approves it, as `Brando.MCP.Tools`
  # calls it, and the link opened through a site's router
  # (`Brando.Test.SiteRouter`, without tenancy here; the hosts of each
  # tenancy mode are in `BrandoWeb.ProposalPreviewHostsTest`).
  # Grouped, one at a time: ProposalFixtures.context/0 inserts the pages "identity" and
  # "naming", whose URIs concurrent transactions would wait on
  use Brando.ConnCase, async: true, group: :shared_locks

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Catalog, as: Grants
  alias Brando.Authorization.Groups
  alias Brando.Authorization.Scope
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Record
  alias Brando.Content.Proposals.Tools
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Sites.Preview
  alias Brando.Test.SiteRouter, as: Router

  setup do
    c = Brando.ProposalFixtures.context()
    Enum.each([c.identity, c.naming], &Brando.Content.create_identifier(Page, &1))
    c
  end

  # What `Brando.MCP.Tools` builds for a call: the actor, no conversation.
  defp mcp(c, fields \\ []), do: struct(%Context{actor: c.user, origin: :mcp, client: "Claude Code"}, fields)

  defp insert_op(c, page, heading) do
    %{
      "op" => "insert_block",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => page.id},
      "module" => "local:#{c.case_module.id}",
      "values" => %{"heading" => heading}
    }
  end

  defp create_op(ref, uri, title \\ "Lobby") do
    %{
      "op" => "create_entry",
      "content_type" => "Brando.Pages.Page",
      "ref" => ref,
      "fields" => %{"title" => title, "uri" => uri, "language" => "en", "template" => "default.html"}
    }
  end

  defp prepare!(context, operations, summary \\ "Add the lobby") do
    assert {:ok, %{proposal_id: id} = review} =
             Tools.call("prepare_proposal", %{"summary" => summary, "operations" => operations}, context)

    assert review.problems == [], inspect(review.problems)
    id
  end

  defp page(page), do: %{"content_type" => "Brando.Pages.Page", "id" => page.id}

  defp preview(context, id, target, args \\ %{}) do
    Tools.call(
      "preview_proposal",
      Map.merge(%{"proposal_id" => id, "target" => target, "preview_target" => "blocks"}, args),
      context
    )
  end

  defp preview!(context, id, target, args \\ %{}) do
    assert {:ok, %{url: url} = result} = preview(context, id, target, args)
    assert {:ok, _} = Jason.encode(result)
    url
  end

  defp set!(id, fields), do: Repo.update_all(from(r in Record, where: r.id == ^id), set: fields)
  defp pages, do: Repo.aggregate(Page, :count)
  defp stored(url), do: Repo.get_by!(Preview, preview_key: Preview.hash_key(key(url)))
  defp key(url), do: url |> URI.parse() |> Map.fetch!(:path) |> Path.basename()

  # The link as a browser opens it: through a site's router, with no login
  defp open(url) do
    path = URI.parse(url).path

    :get
    |> Plug.Test.conn("https://admin.test#{path}")
    |> Map.put(:host, "admin.test")
    |> Router.call(Router.init([]))
  rescue
    # Without tenancy the fallback renders the endpoint's own 404 page, which
    # this test application does not have
    error in Plug.Conn.WrapperError ->
      if Exception.message(error.reason) =~ ~s(no "404" html template),
        do: %{status: 404},
        else: reraise(error, __STACKTRACE__)
  end

  defp opens?(url), do: open(url).status == 200

  describe "a new entry" do
    test "renders the page as proposed, with the site's layout, saving nothing but the snapshot", c do
      pages = pages()
      id = prepare!(mcp(c), [create_op("lobby", "lobby", "The new lobby")])

      assert {:ok, result} = preview(mcp(c), id, %{"new" => "lobby"})
      assert %{url: url, expires_at: expires_at, proposal_id: ^id, shows: "proposed", note: note} = result
      assert url =~ "/__p__/"
      assert note =~ "without a login"

      # 15 minutes, as stored
      minutes = DateTime.diff(expires_at, DateTime.utc_now(), :second) / 60
      assert minutes > 14.9 and minutes <= 15
      assert DateTime.compare(stored(url).expires_at, expires_at) == :eq
      assert stored(url).proposal_id == id

      conn = open(url)
      assert conn.status == 200
      assert conn.resp_body =~ "<html>"
      assert conn.resp_body =~ ~s(<main data-preview="blocks">)
      assert conn.resp_body =~ "The new lobby"
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      # No banner: the page is what a screenshot compares
      refute conn.resp_body =~ ~r/draft|proposal/i

      assert pages() == pages
      assert Repo.get!(Record, id).status == "pending"
    end

    test "has no version before it", c do
      id = prepare!(mcp(c), [create_op("lobby", "lobby")])

      assert {:error, message} = preview(mcp(c), id, %{"new" => "lobby"}, %{"version" => "before"})
      assert message =~ "creates this entry" and message =~ "\"proposed\""
    end
  end

  describe "an existing entry" do
    test "shows the proposed and the saved version, and the editor's shareable link is untouched", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Proposed heading")])

      proposed = preview!(mcp(c), id, page(c.identity))
      before = preview!(mcp(c), id, page(c.identity), %{"version" => "before"})

      assert open(proposed).resp_body =~ "Proposed heading"
      assert {:ok, %{shows: "before"}} = preview(mcp(c), id, page(c.identity), %{"version" => "before"})
      refute open(before).resp_body =~ "Proposed heading"
      assert open(before).resp_body =~ "Identity"

      # The editor's link: two days, no proposal, no robots header of its own
      {:ok, proposal} = Proposals.get(id, c.user)
      assert {:ok, url, days} = Proposals.Preview.share(proposal, {Page, c.identity.id}, c.user, preview_target: :blocks)
      assert days == 2
      assert is_nil(stored(url).proposal_id)
      conn = open(url)
      assert conn.status == 200
      assert get_resp_header(conn, "x-robots-tag") == []
    end

    test "a page its block operations change has its head, with its meta image or without one", c do
      Repo.update_all(from(p in Page, where: p.id == ^c.identity.id), set: [meta_image_id: c.image.id])
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby"), insert_op(c, c.naming, "Lobby")])

      for version <- ["proposed", "before"] do
        args = %{"preview_target" => "head", "version" => version}

        with_image = open(preview!(mcp(c), id, page(c.identity), args)).resp_body
        assert with_image =~ ~r/<meta property="og:image" content="[^"]*#{c.image.sizes["xlarge"]}"/

        without = open(preview!(mcp(c), id, page(c.naming), args)).resp_body
        assert without =~ ~s(<meta property="og:title")
        refute without =~ c.image.sizes["xlarge"]
      end
    end

    test "a meta image the proposal sets is the one its head shows", c do
      sizes = Map.new(c.image.sizes, fn {size, path} -> {size, String.replace(path, "1.jpg", "2.jpg")} end)
      other = Factory.insert(:image, path: "image/2.jpg", sizes: sizes, creator_id: c.user.id)
      Repo.update_all(from(p in Page, where: p.id == ^c.identity.id), set: [meta_image_id: c.image.id])

      set_image = %{"op" => "set_fields", "target" => page(c.identity), "fields" => %{"meta_image_id" => other.id}}
      id = prepare!(mcp(c), [set_image, insert_op(c, c.identity, "Lobby")])

      body = open(preview!(mcp(c), id, page(c.identity), %{"preview_target" => "head"})).resp_body
      assert body =~ ~r/<meta property="og:image" content="[^"]*#{other.sizes["xlarge"]}"/
      refute body =~ c.image.sizes["xlarge"]
    end

    test "a preview target's own preloads decide what the page lists", c do
      for {title, status} <- [{"Published child", :published}, {"Draft child", :draft}],
          do: Factory.insert(:page, creator: c.user, parent_id: c.identity.id, title: title, status: status)

      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])

      for version <- ["proposed", "before"] do
        body =
          open(preview!(mcp(c), id, page(c.identity), %{"preview_target" => "children", "version" => version})).resp_body

        assert body =~ "Published child"
        refute body =~ "Draft child"
      end
    end

    test "entries a proposal lists come with their identifiers", c do
      {:ok, article} =
        Brando.SyncTest.create_article(%{title: "Article", slug: "article", language: "en", status: "published"}, c.user)

      article_target = %{"content_type" => "Brando.SyncTest.Article", "id" => article.id}
      related = %{"related_entries" => [page(c.naming), page(c.identity)]}
      id = prepare!(mcp(c), [%{"op" => "set_fields", "target" => article_target, "fields" => related}])

      body = open(preview!(mcp(c), id, article_target, %{"preview_target" => "related"})).resp_body
      assert body =~ ~r/Naming.*Identity/s

      # A new entry, which has no id to load them through
      fields = Map.merge(related, %{"title" => "New", "slug" => "new", "language" => "en"})
      create = %{"op" => "create_entry", "content_type" => "Brando.SyncTest.Article", "ref" => "new", "fields" => fields}
      id = prepare!(mcp(c), [create])

      body = open(preview!(mcp(c), id, %{"new" => "new"}, %{"preview_target" => "related"})).resp_body
      assert body =~ ~r/Naming.*Identity/s
    end

    test "a list a preview target names still gets what the Blueprint loads beneath it", c do
      {:ok, article} =
        Brando.SyncTest.create_article(%{title: "Article", slug: "article", language: "en", status: "published"}, c.user)

      {:ok, identifier} = Brando.Content.create_identifier(Page, c.identity)
      join = Brando.SyncTest.Article.__schema__(:association, :related_entries).related
      Repo.insert!(struct(join, parent_id: article.id, identifier_id: identifier.id, sequence: 0))

      article_target = %{"content_type" => "Brando.SyncTest.Article", "id" => article.id}
      title = %{"op" => "set_fields", "target" => article_target, "fields" => %{"title" => "Renamed"}}
      id = prepare!(mcp(c), [title])

      for version <- ["proposed", "before"] do
        params = %{"preview_target" => "related_named", "version" => version}
        assert open(preview!(mcp(c), id, article_target, params)).resp_body =~ "Identity"
      end
    end

    test "two calls give two links, each working until its own expiry", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      first = preview!(mcp(c), id, page(c.identity))
      second = preview!(mcp(c), id, page(c.identity), %{"preview_target" => "listing"})

      refute first == second
      assert opens?(first) and opens?(second)

      Repo.update_all(from(p in Preview, where: p.preview_key == ^Preview.hash_key(key(first))),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
      )

      refute opens?(first)
      assert opens?(second)
    end
  end

  describe "the link stops working" do
    test "after the proposal is cancelled", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      url = preview!(mcp(c), id, page(c.identity))
      assert opens?(url)

      assert {:ok, _} = Tools.call("cancel_proposal", %{"proposal_id" => id}, mcp(c))
      refute opens?(url)
    end

    test "after it is replaced", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      url = preview!(mcp(c), id, page(c.identity))

      newer = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby, again")], "The lobby, again")
      assert Repo.get!(Record, id).status == "superseded"
      refute opens?(url)
      assert opens?(preview!(mcp(c), newer, page(c.identity)))
    end

    test "not after approval, but after apply and undo", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      url = preview!(mcp(c), id, page(c.identity))

      assert {:ok, _} = Proposals.approve(id, 1, c.user)
      assert opens?(url)
      # An approved proposal still gets new links
      approved = preview!(mcp(c), id, page(c.identity))
      assert opens?(approved)

      assert {:ok, _} = Proposals.apply(id, 1, c.user)
      refute opens?(url)
      refute opens?(approved)

      assert {:ok, _} = Proposals.undo(id, c.user)
      assert Repo.get!(Record, id).status == "undone"
      refute opens?(url)
    end

    test "after the proposal's own expiry, while the snapshot is still fresh", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      url = preview!(mcp(c), id, page(c.identity))

      set!(id, expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
      assert DateTime.compare(stored(url).expires_at, DateTime.utc_now()) == :gt
      refute opens?(url)
    end

    test "after its 15 minutes, and the purger removes it as it removes shared previews", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      url = preview!(mcp(c), id, page(c.identity))
      preview = stored(url)

      assert {:snooze, seconds} = Brando.Worker.PreviewPurger.perform(%Oban.Job{args: %{"id" => preview.id}})
      assert seconds in 1..900

      past = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
      Repo.update!(Ecto.Changeset.change(preview, expires_at: past))
      refute opens?(url)

      assert :ok = Brando.Worker.PreviewPurger.perform(%Oban.Job{args: %{"id" => preview.id}})
      refute Repo.get(Preview, preview.id)
    end
  end

  describe "no link" do
    test "for a proposal no longer under review, or expired", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])

      for status <- ~w(applied undone superseded cancelled) do
        set!(id, status: status)
        assert {:error, message} = preview(mcp(c), id, page(c.identity))
        assert message =~ "is #{status}"
      end

      set!(id, status: "pending", expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
      assert {:error, message} = preview(mcp(c), id, page(c.identity))
      assert message =~ "expired"
    end

    test "for another person's, another client's, the Assistant's, an older origin-less and another site's proposal",
         c do
      other = Factory.insert(:random_user)
      theirs = prepare!(mcp(c, actor: other), [insert_op(c, c.naming, "Theirs")], "Theirs")
      cursors = prepare!(mcp(c, client: "Cursor"), [insert_op(c, c.naming, "Cursor's")], "Cursor's")

      conversation = %Context{actor: c.user, origin: :assistant, conversation_id: Ecto.UUID.generate()}
      assistants = prepare!(conversation, [insert_op(c, c.identity, "Assistant's")], "Assistant's")

      # Stored before proposals recorded where they came from
      older = prepare!(mcp(c), [insert_op(c, c.identity, "Older")], "Older")
      set!(older, origin: nil)

      elsewhere = prepare!(mcp(c), [insert_op(c, c.naming, "Elsewhere")], "Elsewhere")
      set!(elsewhere, scope: "acme:staging")

      for id <- [theirs, cursors, assistants, older, elsewhere] do
        assert {:error, message} = preview(mcp(c), id, page(c.naming))
        assert message =~ "no proposal", id
        # The same answer whatever the proposal holds
        assert {:error, ^message} = preview(mcp(c), id, %{"new" => "anything"}, %{"version" => "nonsense"})
      end

      for id <- ["not-a-uuid", Ecto.UUID.generate(), 12, nil] do
        assert {:error, message} = preview(mcp(c), id, page(c.naming))
        assert message =~ "no proposal"
      end

      assert Repo.aggregate(Preview, :count) == 0

      # Each is previewed by its own connection
      assert {:ok, _} = preview(mcp(c, client: "Cursor"), cursors, page(c.naming))
      assert {:ok, _} = preview(mcp(c, actor: other), theirs, page(c.naming))
    end

    test "for an entry not in the proposal, a bad target, an unknown view or version", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])

      assert {:error, message} = preview(mcp(c), id, page(c.naming))
      assert message =~ "not part of the proposal"
      assert {:error, ^message} = preview(mcp(c), id, %{"new" => "lobby"})
      assert {:error, ^message} = preview(mcp(c), id, %{"content_type" => "Brando.Users.User", "id" => c.user.id})

      for target <- [nil, "Brando.Pages.Page:1", %{"content_type" => "Brando.Pages.Page"}] do
        assert {:error, message} = preview(mcp(c), id, target)
        assert message =~ "target"
      end

      assert {:error, message} = preview(mcp(c), id, page(c.identity), %{"preview_target" => "nowhere"})
      assert message =~ "Unknown preview target \"nowhere\""
      assert message =~ "blocks" and message =~ "listing"

      assert {:error, message} = preview(mcp(c), id, page(c.identity), %{"version" => "after"})
      assert message =~ "\"proposed\" or \"before\""

      assert Repo.aggregate(Preview, :count) == 0
    end

    test "for a proposal with problems, though its before version is shown", c do
      id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
      set!(id, problems: [%{"index" => 0, "code" => "unknown_block", "message" => "Something to fix"}])

      assert {:error, message} = preview(mcp(c), id, page(c.identity))
      assert message =~ "has problems"
      assert {:ok, %{shows: "before"}} = preview(mcp(c), id, page(c.identity), %{"version" => "before"})
    end

    test "for a proposal that copies a block that is not there, in either version", c do
      copies = [
        %{"op" => "copy_block", "target" => page(c.identity), "block_uid" => "gone", "to" => page(c.naming)},
        %{"op" => "copy_block", "target" => page(c.naming), "block_uid" => "gone"}
      ]

      for op <- copies do
        assert {:ok, %{proposal_id: id, problems: [%{code: :unknown_block}]}} =
                 Tools.call("prepare_proposal", %{"summary" => "Copy", "operations" => [op]}, mcp(c))

        for version <- ["proposed", "before"] do
          assert {:error, message} = preview(mcp(c), id, page(c.naming), %{"version" => version})
          assert message =~ "has problems", "#{version}: #{message}"
        end
      end

      assert Repo.aggregate(Preview, :count) == 0
    end

    test "for a content type without a page preview", c do
      id =
        prepare!(mcp(c), [
          %{
            "op" => "create_entry",
            "content_type" => "Brando.Pages.Fragment",
            "ref" => "footer",
            "fields" => %{"title" => "Footer", "parent_key" => "partials", "key" => "footer", "language" => "en"}
          }
        ])

      assert {:error, "This content type has no page preview."} = preview(mcp(c), id, %{"new" => "footer"})
    end
  end

  describe "permissions" do
    setup c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      # Drafts: changing a published page also takes the publish grant
      for page <- [c.identity, c.naming],
          do: Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [status: :draft])

      :ok
    end

    defp editor!(c, actions) do
      editor = Factory.insert(:random_user, role: :user)
      group = group!(c, editor, actions)
      {editor, group}
    end

    defp group!(c, user, actions) do
      grants =
        Enum.map(actions, &Grants.get(&1, Page).key) ++
          [Grants.get(:read, Brando.Content.Module).key, "brando.admin.access"]

      {:ok, group} =
        Groups.create(Scope.standalone(c.user), %{name: "Editors #{System.unique_integer([:positive])}"}, grants)

      {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), group.id, user.id)
      group
    end

    defp leave!(c, user, group), do: {:ok, :ok} = Groups.remove_member(Scope.standalone(c.user), group.id, user.id)

    test "one who may edit but not export gets a link", c do
      {editor, _group} = editor!(c, [:read, :update])
      refute Brando.Authorization.Engine.can?(Scope.standalone(editor), :export, Page)

      id = prepare!(mcp(c, actor: editor), [insert_op(c, c.identity, "Lobby")])
      assert opens?(preview!(mcp(c, actor: editor), id, page(c.identity)))
      assert opens?(preview!(mcp(c, actor: editor), id, page(c.identity), %{"version" => "before"}))
    end

    test "one who may create but not read gets a link to a new entry, not to an existing one", c do
      {editor, group} = editor!(c, [:read, :update, :create])
      new = prepare!(mcp(c, actor: editor), [create_op("lobby", "lobby")])
      existing = prepare!(mcp(c, actor: editor), [insert_op(c, c.identity, "Lobby")], "Change identity")

      leave!(c, editor, group)
      group!(c, editor, [:create])

      assert opens?(preview!(mcp(c, actor: editor), new, %{"new" => "lobby"}))

      for version <- ["proposed", "before"] do
        assert {:error, _} = preview(mcp(c, actor: editor), existing, page(c.identity), %{"version" => version})
      end
    end

    test "one who can no longer read or edit the entry gets no link, for either version", c do
      {editor, group} = editor!(c, [:read, :update, :create])
      id = prepare!(mcp(c, actor: editor), [insert_op(c, c.identity, "Lobby")])
      new = prepare!(mcp(c, actor: editor), [create_op("lobby", "lobby")], "New")

      leave!(c, editor, group)
      group!(c, editor, [:read])

      for version <- ["proposed", "before"] do
        assert {:error, _} = preview(mcp(c, actor: editor), id, page(c.identity), %{"version" => version})
      end

      # Creating it is no longer theirs either: the proposal is checked again as theirs
      assert {:error, message} = preview(mcp(c, actor: editor), new, %{"new" => "lobby"})
      assert message =~ "has problems"

      assert Repo.aggregate(Preview, :count) == 0
    end
  end

  describe "an entry the proposal moves out of the person's reach" do
    alias Brando.SyncPolicyTest.Article

    setup c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      editor = Factory.insert(:random_user, role: :user)

      # A record policy: one may read and edit the articles one created
      # (`Brando.AuthorizationTestPolicy`)
      grants = [Grants.get(:read, Article).key, Grants.get(:update, Article).key, "brando.admin.access"]
      {:ok, group} = Groups.create(Scope.standalone(c.user), %{name: "Article editors"}, grants)
      {:ok, :ok} = Groups.add_member(Scope.standalone(c.user), group.id, editor.id)

      {:ok, article} =
        Brando.SyncTest.create_article(%{title: "Kept", slug: "kept", language: "en", status: "draft"}, c.user)

      Repo.update_all(from(a in Article, where: a.id == ^article.id), set: [creator_id: editor.id])
      on_exit(fn -> Process.delete(:authorization_test_policy_denies_title) end)
      %{editor: editor, article: article}
    end

    test "gets no link, for either version", c do
      target = %{"content_type" => "Brando.SyncPolicyTest.Article", "id" => c.article.id}
      op = %{"op" => "set_fields", "target" => target, "fields" => %{"title" => "Moved"}}
      id = prepare!(mcp(c, actor: c.editor), [op], "Move it")

      before = preview!(mcp(c, actor: c.editor), id, target, %{"version" => "before", "preview_target" => nil})
      assert open(before).resp_body =~ "Kept"

      # An article titled as the proposal leaves it is now out of the person's reach
      Process.put(:authorization_test_policy_denies_title, "Moved")

      for version <- ["proposed", "before"] do
        assert {:error, "You may not edit this entry as the proposal leaves it."} =
                 preview(mcp(c, actor: c.editor), id, target, %{"version" => version, "preview_target" => nil})
      end

      assert Repo.aggregate(Preview, :count) == 1
    end
  end

  test "is offered only to a tool connected over MCP, marked read-only", c do
    refute "preview_proposal" in Enum.map(Tools.definitions(:assistant), & &1.name)
    assert "preview_proposal" in Enum.map(Tools.definitions(:mcp), & &1.name)

    assert %{annotations: %{readOnlyHint: true, destructiveHint: false}} =
             Enum.find(Brando.MCP.Tools.list(), &(&1.name == "brando_content_preview_proposal"))

    id = prepare!(mcp(c), [insert_op(c, c.identity, "Lobby")])
    assistant = %Context{actor: c.user, origin: :assistant, conversation_id: Ecto.UUID.generate()}
    assert {:error, "Unknown tool" <> _} = preview(assistant, id, page(c.identity))
  end
end
