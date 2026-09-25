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

    html = eventually(view, &(&1 =~ "Ready for your review"))
    assert html =~ "Searched for “Ident”"
    assert html =~ "Prepared the proposal"
    assert html =~ "Prepared a text block for Identity."
    assert html =~ "Add a Text block"
    assert html =~ "Written in the assistant"
    assert html =~ "Live page changes"
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

  test "another user's conversation is not shown", %{conn: conn} do
    other = Brando.Factory.insert(:random_user)
    {:ok, conversation} = Agent.start_conversation(other)
    assert {:error, {:live_redirect, %{to: "/admin/assistant"}}} = live(conn, "/admin/assistant/#{conversation.id}")
  end
end
