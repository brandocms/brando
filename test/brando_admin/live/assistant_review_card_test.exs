defmodule BrandoAdmin.AssistantReviewCardTest do
  @moduledoc """
  The Apply click approves what the card shows, so a model's reply and a
  card hide nothing: the assistant's images do not load by themselves, and a
  change's whole text, its addresses and its markup are on the card.
  """
  use Brando.LiveCase
  use Brando.Test

  require Ecto.Query

  alias Brando.AI.Agent
  alias Brando.AIStub
  alias Brando.Pages.Page

  @tail "A last sentence past any excerpt."
  @address "https://elsewhere.invalid/landing"
  @opening String.duplicate("Harmless opening words. ", 6)

  setup %{current_user: user} do
    AIStub.configure()
    fixtures = Brando.ProposalFixtures.context()
    Brando.Content.create_identifier(Page, fixtures.identity)
    Map.merge(fixtures, %{current_user: user})
  end

  defp first_uid(page) do
    (Repo.preload(Repo.get!(Page, page.id), entry_blocks: :block).entry_blocks |> hd()).block.uid
  end

  defp text_op(page, text) do
    %{
      "op" => "set_block_text",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => page.id},
      "block_uid" => first_uid(page),
      "ref" => "body",
      "text" => text
    }
  end

  defp propose(conn, user, ops) do
    {:ok, conversation} = Agent.start_conversation(user)

    AIStub.script([
      {:tools, [{"prepare_proposal", %{"summary" => "Tighten", "operations" => ops}}]},
      {:text, "Prepared."}
    ])

    {:ok, %{status: "completed"}} = Agent.send_message(conversation.id, "Tighten it", user, sync: true)
    {:ok, conversation} = Agent.get_conversation(conversation.id, user)
    {:ok, proposal} = Brando.Content.Proposals.get(conversation.proposal_id, user)
    {:ok, view, _} = live(conn, "/admin/assistant/#{conversation.id}")
    {view, proposal}
  end

  defp apply!(proposal, user) do
    {:ok, _} = Brando.Content.Proposals.approve(proposal.id, proposal.version, user)
    {:ok, _} = Brando.Content.Proposals.apply(proposal.id, proposal.version, user)
  end

  defp change(view) do
    html = view |> render() |> Floki.parse_document!()

    {html |> Floki.find(".assistant-fields del") |> Floki.text(),
     html |> Floki.find(".assistant-fields ins") |> Floki.text()}
  end

  describe "the assistant's reply" do
    test "writes an image as a link, so nothing loads by itself", %{conn: conn, current_user: user} do
      {:ok, conversation} = Agent.start_conversation(user)

      reply = """
      Here: ![the chart](https://elsewhere.invalid/x.png?data=secret)
      ![](https://elsewhere.invalid/noalt.png)
      ![by reference][ref]

      [ref]: https://elsewhere.invalid/ref.png
      """

      AIStub.script([{:text, reply}])
      {:ok, %{status: "completed"}} = Agent.send_message(conversation.id, "Hello", user, sync: true)
      {:ok, view, _} = live(conn, "/admin/assistant/#{conversation.id}")

      refute has_element?(view, ".assistant-text img")
      assert has_element?(view, ~s(.assistant-text a[href="https://elsewhere.invalid/x.png?data=secret"]), "the chart")
      assert has_element?(view, ~s(.assistant-text a[href="https://elsewhere.invalid/noalt.png"]), "noalt.png")
      assert has_element?(view, ~s(.assistant-text a[href="https://elsewhere.invalid/ref.png"]), "by reference")
    end
  end

  describe "a text change" do
    test "shows the whole text and its link address", %{conn: conn, current_user: user} = c do
      text = ~s(<p>#{@opening}#{@tail} <a href="#{@address}">read more</a></p>)
      {view, proposal} = propose(conn, user, [text_op(c.identity, text)])

      {_before, proposed} = change(view)
      assert proposed =~ @tail
      assert proposed =~ @address

      apply!(proposal, user)
    end

    test "a change only in an address shows both addresses", %{conn: conn, current_user: user} = c do
      {_view, first} =
        propose(conn, user, [text_op(c.identity, ~s(<p>Short <a href="https://good.invalid/">more</a></p>))])

      apply!(first, user)

      {view, _} = propose(conn, user, [text_op(c.identity, ~s(<p>Short <a href="#{@address}">more</a></p>))])
      {before, proposed} = change(view)

      assert before =~ "https://good.invalid/"
      assert proposed =~ @address
    end

    test "a change past the first words shows what differs", %{conn: conn, current_user: user} = c do
      {_view, first} = propose(conn, user, [text_op(c.identity, "<p>#{@opening}The old ending.</p>")])
      apply!(first, user)

      {view, _} = propose(conn, user, [text_op(c.identity, "<p>#{@opening}#{@tail}</p>")])
      {before, proposed} = change(view)

      assert before =~ "The old ending."
      assert proposed =~ @tail
      assert before != proposed
      # The unchanged words are left out, past some context
      assert String.starts_with?(proposed, "…")
      refute String.length(proposed) > String.length(@tail) + 42
    end

    test "a change only in formatting shows the markup", %{conn: conn, current_user: user} = c do
      {_view, first} = propose(conn, user, [text_op(c.identity, "<p>Plain words</p>")])
      apply!(first, user)

      {view, _} = propose(conn, user, [text_op(c.identity, "<p>Plain <strong>words</strong></p>")])
      {before, proposed} = change(view)

      assert before =~ "<p>Plain words</p>"
      assert proposed =~ "<strong>words</strong>"
    end

    test "shows remote media and styling, and not plain formatting", %{conn: conn, current_user: user} = c do
      text =
        ~s(<p><strong>Bold</strong> <span style="color: red">red</span></p>) <>
          ~s(<p><img src="https://elsewhere.invalid/x.png"></p>)

      {view, _} = propose(conn, user, [text_op(c.identity, text)])
      {_before, proposed} = change(view)

      assert proposed =~ ~s(<span style="color: red">red</span>)
      assert proposed =~ ~s(<img src="https://elsewhere.invalid/x.png">)
      refute proposed =~ "<strong>"
    end
  end

  describe "text one parser reads differently from another" do
    test "a Markdown autolink shows", %{conn: conn, current_user: user} = c do
      {view, _} = propose(conn, user, [text_op(c.identity, "<p>Read &lt;https://elsewhere.invalid/x&gt; today</p>")])
      {_before, proposed} = change(view)

      assert proposed =~ "https://elsewhere.invalid/x"
    end

    test "an address with a scheme the sanitizer drops shows", %{conn: conn, current_user: user} = c do
      {view, _} = propose(conn, user, [text_op(c.identity, ~s(<p><a href="steam://run/1">Free</a></p>))])
      {_before, proposed} = change(view)

      assert proposed =~ "steam://run/1"
    end

    test "text after an unclosed bracket shows", %{conn: conn, current_user: user} = c do
      {view, _} = propose(conn, user, [text_op(c.identity, "If a&lt;b see more of this")])
      {_before, proposed} = change(view)

      assert proposed =~ "see more of this"
    end

    test "an attribute after a slash still shows", %{conn: conn, current_user: user} = c do
      {view, _} = propose(conn, user, [text_op(c.identity, ~s(<p>Offer: <a/href="#{@address}">more</a></p>))])
      {_before, proposed} = change(view)

      assert proposed =~ @address
    end

    test "a stray end tag hides nothing after it", %{conn: conn, current_user: user} = c do
      text = ~s(<p>Short.</p></floki><p><a href="#{@address}">more</a></p>)
      {view, _} = propose(conn, user, [text_op(c.identity, text)])
      {_before, proposed} = change(view)

      assert proposed =~ @address
    end
  end

  test "a change only in line breaks shows them", %{conn: conn, current_user: user} = c do
    field = fn value ->
      %{
        "op" => "set_fields",
        "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
        "fields" => %{"meta_description" => value}
      }
    end

    {_view, first} = propose(conn, user, [field.("First sentence. Second sentence.")])
    apply!(first, user)

    {view, _} = propose(conn, user, [field.("First sentence.\n\nSecond sentence.")])
    {before, proposed} = change(view)

    assert before == "First sentence. Second sentence."
    assert proposed =~ "↵"
  end

  test "inline formatting adds no spaces to the words", %{conn: conn, current_user: user} = c do
    {view, _} = propose(conn, user, [text_op(c.identity, "<p>Pay 1<strong>0</strong>0 dollars.</p><p>Then more.</p>")])
    {_before, proposed} = change(view)

    assert proposed == "Pay 100 dollars. Then more."
  end

  test "a long text reopened after apply shows the text, not its tail", %{conn: conn, current_user: user} = c do
    {_view, proposal} = propose(conn, user, [text_op(c.identity, "<p>#{@opening}#{@tail}</p>")])
    apply!(proposal, user)

    {:ok, reopened, _} = live(conn, "/admin/assistant/#{proposal.conversation_id}")
    {_before, proposed} = change(reopened)

    assert proposed =~ "Harmless opening words."
    assert proposed =~ @tail
  end

  describe "a field change" do
    test "shows the whole value, and what differs in a long one", %{conn: conn, current_user: user} = c do
      field = fn value ->
        %{
          "op" => "set_fields",
          "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
          "fields" => %{"meta_description" => value}
        }
      end

      {_view, first} = propose(conn, user, [field.("#{@opening}The old ending.")])
      apply!(first, user)

      {view, _} = propose(conn, user, [field.("#{@opening}#{@tail}")])
      {before, proposed} = change(view)

      assert before =~ "The old ending."
      assert proposed =~ @tail
    end
  end

  test "a plain field's angle bracket is what it says", %{conn: conn, current_user: user} = c do
    Brando.Repo.update_all(Ecto.Query.from(p in Page, where: p.id == ^c.identity.id), set: [title: "R<D og utvikling"])

    field = %{
      "op" => "set_fields",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => c.identity.id},
      "fields" => %{"title" => "Pris på utvikling"}
    }

    {view, _} = propose(conn, user, [field])
    {before, proposed} = change(view)

    assert before == "R<D og utvikling"
    assert proposed == "Pris på utvikling"
  end
end
