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
    assert html =~ "Prepared the proposal"
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

      view |> element(~s(footer button[phx-value-key="#{identity}"])) |> render_click()
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
end
