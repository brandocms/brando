defmodule BrandoAdmin.AssistantLiveTest do
  use Brando.LiveCase
  alias Brando.AI.Agent
  alias Brando.AIStub
  alias Brando.Content.Transfer.Catalog
  alias Brando.Pages.Page

  setup %{current_user: user} do
    AIStub.configure(shared: true)
    fixtures = Brando.ProposalFixtures.context()
    Brando.Content.create_identifier(Page, fixtures.identity)
    Map.merge(fixtures, %{current_user: user})
  end

  defp eventually(view, fun, tries \\ 200) do
    html = render(view)

    cond do
      fun.(html) -> html
      tries == 0 -> flunk("Timed out waiting for the view. Last render:\n" <> html)
      true -> Process.sleep(50) && eventually(view, fun, tries - 1)
    end
  end

  test "an empty workspace explains the next step", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/assistant")
    assert html =~ "No proposal yet"
    assert html =~ "Describe the changes you want"
  end

  describe "opened from the block editor" do
    test "shows the selected entry and starts the conversation on it", %{conn: conn} = c do
      AIStub.script([{:text, "Which part of Identity should change?"}])
      path = "/admin/assistant?content_type=Brando.Pages.Page&id=#{c.identity.id}&field=blocks"
      {:ok, view, html} = live(conn, path)

      assert html =~ "Working on"
      assert has_element?(view, "#assistant-destination a[href='/admin/pages/update/#{c.identity.id}']", "Identity")
      assert has_element?(view, "#assistant-destination dd", "Blocks")
      assert html =~ "The assistant reads the saved entry. Unsaved changes in the editor are not included"
      # Opening the workspace writes nothing, not even a conversation.
      assert Agent.list_conversations(c.current_user) == []

      view |> form("#assistant-composer", %{message: "Tighten the introduction"}) |> render_submit()
      [conversation] = Agent.list_conversations(c.current_user)
      assert_patch(view, "/admin/assistant/#{conversation.id}")
      assert %{"content_type" => "Brando.Pages.Page", "field" => "blocks", "title" => "Identity"} = conversation.target

      eventually(view, &(&1 =~ "Which part of Identity should change?"))
      assert has_element?(view, "#assistant-destination", "Identity")
      assert length(Catalog.load!(Page, c.identity.id, c.current_user).entry_blocks) == 3

      # A new conversation starts without the entry.
      view |> element("a", "New conversation") |> render_click()
      refute has_element?(view, "#assistant-destination")
    end

    test "an entry that cannot be used is not selected", %{conn: conn} = c do
      {:ok, view, _} = live(conn, "/admin/assistant?content_type=Brando.Pages.Page&id=-1&field=blocks")
      refute has_element?(view, "#assistant-destination")

      {:ok, view, _} = live(conn, "/admin/assistant?content_type=Brando.Pages.Page&id=#{c.identity.id}&field=nope")
      refute has_element?(view, "#assistant-destination")
    end
  end

  describe "Build with AI in the block editor" do
    test "links to the assistant for the saved entry and field", %{conn: conn} = c do
      {view, _html} = live_form(conn, "/admin/pages/update/#{c.identity.id}")
      html = await_selector(view, "[data-testid=build-with-ai]")
      [href] = html |> Floki.parse_document!() |> Floki.attribute("[data-testid=build-with-ai]", "href")

      assert %URI{path: "/admin/assistant", query: query} = URI.parse(href)

      assert URI.decode_query(query) == %{
               "content_type" => "Brando.Pages.Page",
               "id" => to_string(c.identity.id),
               "field" => "blocks"
             }

      # A new tab: the editor, and anything unsaved in it, stays open.
      assert has_element?(view, "a[data-testid=build-with-ai][target=_blank]", "Build with AI")
    end

    test "asks to save a new entry first", %{conn: conn} do
      {view, _html} = live_form(conn, "/admin/pages/create")
      await_selector(view, ".block-field-assistant")
      assert has_element?(view, ".block-field-assistant button[disabled]", "Build with AI")
      assert has_element?(view, ".block-field-assistant-hint", "Save the entry to build it with AI")
      refute has_element?(view, "[data-testid=build-with-ai]")
    end

    test "is hidden without a model", %{conn: conn} = c do
      Application.delete_env(:brando, Brando.AI)
      {view, _html} = live_form(conn, "/admin/pages/update/#{c.identity.id}")
      await_selector(view, ".blocks-wrapper")
      refute has_element?(view, ".block-field-assistant")
    end

    test "is hidden for users without the assistant permission", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      alias Brando.Authorization.{Catalog, Groups, Scope}
      editor = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      scope = Scope.standalone(c.current_user)

      {:ok, group} =
        Groups.create(scope, %{name: "Page editors"}, [
          Catalog.get(:access, :backend).key,
          Catalog.get(:read, Page).key,
          Catalog.get(:update, Page).key
        ])

      {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)
      conn = log_in_user(build_conn(), editor)

      {view, _html} = live_form(conn, "/admin/pages/update/#{c.identity.id}")
      await_selector(view, ".blocks-wrapper")
      refute has_element?(view, ".block-field-assistant")

      {:ok, assistants} = Groups.create(scope, %{name: "Assistant users"}, [Catalog.get(:use, :assistant).key])
      {:ok, :ok} = Groups.add_member(scope, assistants.id, editor.id)
      {view, _html} = live_form(conn, "/admin/pages/update/#{c.identity.id}")
      await_selector(view, "[data-testid=build-with-ai]")
    end
  end

  test "a message produces a reviewed proposal that one click applies", %{conn: conn} = c do
    op = %{
      "op" => "insert_block",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
      "module" => "local:#{c.text_module.id}",
      "texts" => %{"body" => "<p>Written in the assistant</p>"}
    }

    AIStub.script([
      {:tools, [{"search_entries", %{"query" => "Ident", "content_type" => "Brando.Pages.Page"}}]},
      {:tools, [{"prepare_proposal", %{"summary" => "A new text block on Identity", "operations" => [op]}}]},
      {:text, "Prepared a text block for Identity."}
    ])

    {:ok, view, _} = live(conn, "/admin/assistant")
    view |> form("#assistant-composer", %{message: "Add a text block to Identity"}) |> render_submit()
    [conversation] = Agent.list_conversations(c.current_user)
    assert_patch(view, "/admin/assistant/#{conversation.id}")

    # The proposal arrives before the model's final reply.
    html = eventually(view, &(&1 =~ "Prepared a text block for Identity."))
    assert html =~ "Ready for your review"
    assert html =~ "Searched for “Ident”"
    assert html =~ "Prepared version 1 of the proposal"
    assert html =~ "Add a Text block"
    assert html =~ "Written in the assistant"
    assert html =~ "Live page"
    assert length(Catalog.load!(Page, c.identity.id, c.current_user).entry_blocks) == 3

    view |> element("button.assistant-apply") |> render_click()
    html = eventually(view, &(&1 =~ "Applied"))
    assert html =~ "The changes are saved"
    assert length(Catalog.load!(Page, c.identity.id, c.current_user).entry_blocks) == 4
    refute has_element?(view, "button.assistant-apply")
  end

  test "steps name what they read, and the cost so far is shown unless switched off", %{conn: conn} = c do
    AIStub.script([
      {:tools, [{"entry_outline", %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id}}]},
      {:text, "Identity has three text blocks."}
    ])

    {:ok, view, _} = live(conn, "/admin/assistant")
    view |> form("#assistant-composer", %{message: "What is on Identity?"}) |> render_submit()
    html = eventually(view, &(&1 =~ "Identity has three text blocks."))
    assert html =~ "Read “Identity”"

    [conversation] = Agent.list_conversations(c.current_user)
    run = Agent.latest_run(conversation.id, c.current_user)
    run |> Ecto.Changeset.change(cost: 0.4242) |> Brando.Repo.update!()

    {:ok, view, _} = live(conn, "/admin/assistant/#{conversation.id}")
    assert has_element?(view, ".assistant-cost", "Estimated cost so far: $0.42")

    previous = Application.get_env(:brando, Agent, [])
    Application.put_env(:brando, Agent, Keyword.put(previous, :show_cost, false))
    on_exit(fn -> Application.put_env(:brando, Agent, previous) end)

    {:ok, view, _} = live(conn, "/admin/assistant/#{conversation.id}")
    refute has_element?(view, ".assistant-cost")
  end

  test "the assistant asks for media, and the editor picks from its suggestions", %{conn: conn} = c do
    AIStub.script([
      {:tools, [{"request_media", %{"kind" => "image", "reason" => "Photos of the typeface", "query" => "Title one"}}]},
      {:text, "Which images of the typeface should I use?"},
      {:tools, [{"list_attachments", %{}}]},
      {:text, "I will use image1."}
    ])

    {:ok, view, _} = live(conn, "/admin/assistant")
    view |> form("#assistant-composer", %{message: "Write an insight article about the typeface"}) |> render_submit()
    eventually(view, &(&1 =~ "Which images of the typeface should I use?"))

    assert has_element?(view, ".assistant-request.is-open", "The assistant asks for images")
    assert has_element?(view, ".assistant-request-reason", "Photos of the typeface")
    suggestion = ~s(.assistant-request-item[phx-value-id="#{c.image.id}"])
    assert has_element?(view, suggestion)

    view |> element(suggestion) |> render_click()
    assert has_element?(view, suggestion <> ".is-picked", "image1")

    view |> element(".assistant-request .assistant-apply") |> render_click()
    eventually(view, &(&1 =~ "I will use image1."))
    assert has_element?(view, ".assistant-bubble", "I have attached the media. Use it.")
    refute has_element?(view, ".assistant-request.is-open")
  end

  test "uploads reserve aliases in the order they were chosen", %{conn: conn} = c do
    {:ok, conversation} = Agent.start_conversation(c.current_user)
    {:ok, view, _} = live(conn, "/admin/assistant/#{conversation.id}")

    send(
      view.pid,
      {:assets_reserved, %{"kind" => "ai_conversation"},
       [
         %{ref: "first", asset_type: "image", filename: "big.jpg"},
         %{ref: "second", asset_type: "image", filename: "small.jpg"}
       ]}
    )

    html = eventually(view, &(&1 =~ "image2"))
    assert html =~ "Uploading…"

    # The second, smaller file finishes first and still becomes image2.
    small = Brando.Factory.insert(:image, creator_id: c.current_user.id, path: "images/small.jpg")
    send(view.pid, {:asset_ready, %{"kind" => "ai_conversation", "upload_ref" => "second"}, small})
    eventually(view, &(length(String.split(&1, "Uploading…")) == 2))

    {:ok, conversation} = Agent.get_conversation(conversation.id, c.current_user)
    assert [%{"alias" => "image1", "id" => nil}, %{"alias" => "image2", "id" => id}] = conversation.attachments
    assert id == small.id
  end

  test "the image picker browses the whole library, and picking toggles an attachment", %{conn: conn} = c do
    {:ok, conversation} = Agent.start_conversation(c.current_user)
    {:ok, view, _} = live(conn, "/admin/assistant/#{conversation.id}")

    image =
      Brando.Factory.insert(:image,
        creator_id: c.current_user.id,
        path: "images/ferry.jpg",
        config_target: "image:Other:cover",
        status: :processed
      )

    view |> element("button[title='Attach images from the media library']") |> render_click()
    assert has_element?(view, "#image-picker [data-id='#{image.id}']")

    render_click(view, "select_image", %{"id" => to_string(image.id)})
    {:ok, conversation} = Agent.get_conversation(conversation.id, c.current_user)
    assert [%{"alias" => "image1", "kind" => "image", "id" => id}] = conversation.attachments
    assert id == image.id

    render_click(view, "select_image", %{"id" => to_string(image.id)})
    {:ok, conversation} = Agent.get_conversation(conversation.id, c.current_user)
    assert conversation.attachments == []
  end

  test "another user's conversation is not shown", %{conn: conn} do
    other = Brando.Factory.insert(:random_user)
    {:ok, conversation} = Agent.start_conversation(other)
    assert {:error, {:live_redirect, %{to: "/admin/assistant"}}} = live(conn, "/admin/assistant/#{conversation.id}")
  end

  describe "page preview" do
    setup %{current_user: user} = c do
      uid = Brando.Utils.generate_uid()

      ops = [
        %Brando.Content.Proposals.CreateEntry{
          schema: Page,
          ref: "sommerro",
          fields: %{title: "Sommerro", uri: "sommerro", language: "en", template: "default.html"}
        },
        %Brando.Content.Proposals.InsertBlock{
          target: {Page, c.identity.id},
          module: c.text_module.id,
          uid: uid,
          texts: %{body: "<p>Written in the assistant</p>"}
        }
      ]

      {:ok, conversation} = Agent.start_conversation(user)
      {:ok, proposal} = Brando.Content.Proposals.propose(ops, user, conversation_id: conversation.id)

      conversation
      |> Ecto.Changeset.change(proposal_id: proposal.id)
      |> Brando.Repo.update!()

      %{conversation: conversation, uid: uid, proposal: proposal}
    end

    defp frame_key(html) do
      [key] = Regex.run(~r/__livepreview\?key=([A-Za-z0-9_-]+)/, html, capture: :all_but_first)
      key
    end

    test "renders the proposed page and its saved version without saving", %{conn: conn} = c do
      {:ok, view, _} = live(conn, "/admin/assistant/#{c.conversation.id}")
      identity = "Brando.Pages.Page:#{c.identity.id}"

      view |> element(~s(button.assistant-card-preview[phx-value-key="#{identity}"])) |> render_click()
      html = render(view)
      assert html =~ "Page preview"

      # The test app's default Page view cannot render these pages: the error
      # is shown honestly, with a retry, and the named views stay available.
      assert html =~ "The page could not be rendered"
      assert has_element?(view, ~s(button[phx-click="preview"][phx-value-key="#{identity}"]), "Try again")

      html = view |> element(~s(button[phx-value-target="blocks"])) |> render_click()
      proposed_key = frame_key(html)
      assert {:ok, proposed} = Brando.LivePreview.get_cache(proposed_key)
      assert proposed =~ "Written in the assistant"
      assert proposed =~ "<!-- [+:B<#{c.uid}>] -->"
      assert html =~ ~s(data-highlight="[&quot;#{c.uid}&quot;]")

      html = view |> element(~s(button[phx-value-version="before"])) |> render_click()
      before_key = frame_key(html)
      assert before_key != proposed_key
      assert {:ok, before} = Brando.LivePreview.get_cache(before_key)
      refute before =~ "Written in the assistant"
      assert html =~ ~s(data-highlight="[]")

      html = view |> element(~s(nav button[phx-value-key="new:sommerro"])) |> render_click()
      assert html =~ "This page has not been created yet"

      # Another entry starts on its content type's default view.
      view |> element(~s(button[phx-value-version="proposed"])) |> render_click()
      html = view |> element(~s(button[phx-value-target="blocks"])) |> render_click()
      new_key = frame_key(html)
      assert {:ok, created} = Brando.LivePreview.get_cache(new_key)
      assert created =~ "Sommerro"

      view |> element("button", "All changes") |> render_click()
      assert has_element?(view, ".assistant-cards")
      assert length(Catalog.load!(Page, c.identity.id, c.current_user).entry_blocks) == 3
    end
  end

  describe "child block changes" do
    setup %{current_user: user} = c do
      c = Brando.ProposalFixtures.multi_context(c)
      [alpha, beta, gamma] = c.child_uids
      target = {Page, c.work.id}

      ops = [
        %Brando.Content.Proposals.SetBlockValues{target: target, block_uid: beta, values: %{size: "50"}},
        %Brando.Content.Proposals.MoveBlock{target: target, block_uid: gamma, placement: {:after, beta}},
        %Brando.Content.Proposals.DeleteBlock{target: target, block_uid: alpha}
      ]

      {:ok, conversation} = Agent.start_conversation(user)
      {:ok, proposal} = Brando.Content.Proposals.propose(ops, user, conversation_id: conversation.id)
      conversation |> Ecto.Changeset.change(proposal_id: proposal.id) |> Brando.Repo.update!()
      Map.put(c, :conversation, conversation)
    end

    test "the review names each entry, shows values before and after, moves and removals", %{conn: conn} = c do
      {:ok, view, html} = live(conn, "/admin/assistant/#{c.conversation.id}")

      assert html =~ "Ready for your review"
      assert has_element?(view, ".assistant-counts", "1 moved block")
      assert has_element?(view, ".assistant-counts", "1 deletion")

      assert html =~ "Change settings of “Project” · 2 of 3 in “Projects” · Beta"
      assert has_element?(view, ".assistant-fields dt", "Size")
      assert has_element?(view, ".assistant-fields del", "Full (100)")
      assert has_element?(view, ".assistant-fields ins", "Half (50)")

      assert html =~ "New order in “Projects”"
      assert has_element?(view, ".assistant-order li:nth-child(2).is-moved", "Gamma")
      assert has_element?(view, ".assistant-order li:nth-child(1)", "Beta")
      assert has_element?(view, ".assistant-order li:nth-child(1) .assistant-order-value.is-changed", "Size: Half (50)")

      assert has_element?(view, ".assistant-change-title.is-removal", "Remove “Project” · 1 of 3 in “Projects” · Alpha")
      # The removed entry's video identifies it.
      assert has_element?(view, ".assistant-thumb.is-video")

      view |> element("button.assistant-apply") |> render_click()
      eventually(view, &(&1 =~ "Applied"))

      [_, multi] = Catalog.load!(Page, c.work.id, c.current_user).entry_blocks
      assert Enum.map(multi.block.children, & &1.uid) == tl(c.child_uids)
    end

    test "switching a ref off is reviewed with the block it belongs to", %{conn: conn} = c do
      [alpha | _] = c.child_uids

      op = %Brando.Content.Proposals.SetBlockActive{
        target: {Page, c.work.id},
        block_uid: alpha,
        ref: "clip",
        active: false
      }

      {:ok, proposal} = Brando.Content.Proposals.propose([op], c.current_user, conversation_id: c.conversation.id)
      c.conversation |> Ecto.Changeset.change(proposal_id: proposal.id) |> Brando.Repo.update!()

      {:ok, view, _html} = live(conn, "/admin/assistant/#{c.conversation.id}")

      assert has_element?(
               view,
               ".assistant-change-title.is-removal",
               "Turn off Clip in “Project” · 1 of 3 in “Projects” · Alpha"
             )

      assert has_element?(view, ".assistant-placement", "It is kept, but not shown on the page.")
      assert has_element?(view, ".assistant-thumb.is-video")
    end

    test "settings, details and copies are reviewed", %{conn: conn} = c do
      [alpha | _] = c.child_uids
      target = {Page, c.work.id}

      ops = [
        %Brando.Content.Proposals.SetRefConfig{target: target, block_uid: alpha, ref: "clip", config: %{autoplay: true}},
        %Brando.Content.Proposals.SetBlockDetails{target: target, block_uid: alpha, anchor: "alpha"},
        %Brando.Content.Proposals.CopyBlock{target: target, block_uid: alpha}
      ]

      {:ok, proposal} = Brando.Content.Proposals.propose(ops, c.current_user, conversation_id: c.conversation.id)
      c.conversation |> Ecto.Changeset.change(proposal_id: proposal.id) |> Brando.Repo.update!()

      {:ok, view, _html} = live(conn, "/admin/assistant/#{c.conversation.id}")

      assert has_element?(
               view,
               ".assistant-change-title",
               "Change Clip settings in “Project” · 1 of 3 in “Projects” · Alpha"
             )

      assert has_element?(view, ".assistant-fields ins", "true")
      assert has_element?(view, ".assistant-change-title", "Change the details of “Project”")
      assert has_element?(view, ".assistant-order li:last-child .assistant-order-mark", "Copy")
    end

    test "a change is left out, and the conversation says so", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/assistant/#{c.conversation.id}")
      assert has_element?(view, ".assistant-eyebrow", "version 1")

      view |> element(~s(button.assistant-leave-out[phx-value-operations="0"])) |> render_click()

      assert has_element?(view, ".assistant-eyebrow", "version 2")
      refute render(view) =~ "Change settings of “Project” · 2 of 3"
      assert has_element?(view, ".assistant-bubble", "Left out of the proposal: “Project” · 2 of 3 in “Projects” · Beta")

      # The rest is still there, and an order has no leave-out button.
      assert has_element?(view, ".assistant-order")
      assert has_element?(view, ".assistant-change-title.is-removal")
    end

    test "applied changes can be undone", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/assistant/#{c.conversation.id}")
      view |> element("button.assistant-apply") |> render_click()
      assert has_element?(view, "button.assistant-undo")

      view |> element("button.assistant-undo") |> render_click()
      assert has_element?(view, "h2", "Undone")
      refute has_element?(view, "button.assistant-undo")
      assert length(Catalog.load!(Page, c.work.id, c.current_user).entry_blocks) == 2
      [_, multi] = Catalog.load!(Page, c.work.id, c.current_user).entry_blocks
      assert Enum.map(multi.block.children, & &1.uid) == c.child_uids
    end

    test "a review link opens the proposal read-only for a colleague", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/assistant/#{c.conversation.id}")
      view |> element("button", "Share for review") |> render_click()
      [link] = view |> render() |> Floki.parse_document!() |> Floki.attribute("#assistant-review-link", "value")
      path = URI.parse(link).path

      colleague = Brando.Factory.insert(:random_user, config: %Brando.Users.UserConfig{})
      {:ok, shared, html} = live(log_in_user(build_conn(), colleague), path)
      assert html =~ "Proposal for review"
      assert has_element?(shared, ".assistant-order")
      refute has_element?(shared, "button.assistant-apply")
      refute has_element?(shared, ".assistant-leave-out")
      refute has_element?(shared, "#assistant-composer")

      assert {:error, {:live_redirect, %{to: "/admin/assistant"}}} =
               live(log_in_user(build_conn(), colleague), "/admin/assistant/shared/nope")
    end

    test "a new entry can be published as it is applied", %{conn: conn} = c do
      ops = [
        %Brando.Content.Proposals.CreateEntry{
          schema: Page,
          ref: "news",
          fields: %{title: "News", uri: "news", language: "en", template: "default.html"}
        }
      ]

      {:ok, proposal} = Brando.Content.Proposals.propose(ops, c.current_user, conversation_id: c.conversation.id)
      c.conversation |> Ecto.Changeset.change(proposal_id: proposal.id) |> Brando.Repo.update!()

      {:ok, view, _html} = live(conn, "/admin/assistant/#{c.conversation.id}")
      view |> element(~s(.assistant-publish input[phx-value-key="new:news"])) |> render_click()
      view |> element("button.assistant-apply") |> render_click()
      assert has_element?(view, ".assistant-receipt .assistant-badge", "Published")
      assert Brando.Repo.get_by!(Page, uri: "news").status == :published
    end

    test "an entry with placeholders lists them and stays a draft", %{conn: conn} = c do
      ops = [
        %Brando.Content.Proposals.CreateEntry{
          schema: Page,
          ref: "news",
          fields: %{
            title: "News",
            uri: "news",
            language: "en",
            template: "default.html",
            meta_description: "Opened in [[year]]"
          }
        }
      ]

      {:ok, proposal} = Brando.Content.Proposals.propose(ops, c.current_user, conversation_id: c.conversation.id)
      c.conversation |> Ecto.Changeset.change(proposal_id: proposal.id) |> Brando.Repo.update!()

      {:ok, view, _html} = live(conn, "/admin/assistant/#{c.conversation.id}")
      assert has_element?(view, ".assistant-placeholders", "1 place needs your input")
      assert has_element?(view, ".assistant-placeholders mark", "year")
      assert has_element?(view, ~s(.assistant-publish input[phx-value-key="new:news"][disabled]))

      # Even if it was ticked before, it is applied as a draft.
      render_click(view, "toggle_publish", %{"key" => "new:news"})
      view |> element("button.assistant-apply") |> render_click()
      assert Brando.Repo.get_by!(Page, uri: "news").status == :draft
    end

    test "a review link can show some of the entries", %{conn: conn} = c do
      ops = [
        %Brando.Content.Proposals.SetFields{target: {Page, c.work.id}, fields: %{title: "Work, renamed"}},
        %Brando.Content.Proposals.CreateEntry{
          schema: Page,
          ref: "news",
          fields: %{title: "News", uri: "news", language: "en", template: "default.html"}
        }
      ]

      {:ok, proposal} = Brando.Content.Proposals.propose(ops, c.current_user, conversation_id: c.conversation.id)
      c.conversation |> Ecto.Changeset.change(proposal_id: proposal.id) |> Brando.Repo.update!()

      {:ok, view, _html} = live(conn, "/admin/assistant/#{c.conversation.id}")
      view |> element("button", "Share for review") |> render_click()
      assert has_element?(view, ".assistant-share-choice input[value='new:news'][checked]")

      view |> form(".assistant-share-choice", %{"keys" => ["new:news"]}) |> render_submit()
      [link] = view |> render() |> Floki.parse_document!() |> Floki.attribute("#assistant-review-link", "value")

      colleague = Brando.Factory.insert(:random_user, config: %Brando.Users.UserConfig{})
      {:ok, shared, _html} = live(log_in_user(build_conn(), colleague), URI.parse(link).path)
      assert has_element?(shared, ".assistant-card", "News")
      refute has_element?(shared, ".assistant-card", "Work, renamed")
    end
  end
end
