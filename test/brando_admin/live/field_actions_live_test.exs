defmodule BrandoAdmin.FieldActionsLiveTest do
  # The test article's subtitle declares two AI actions (`ai_actions:` in
  # test/support/blueprints/synced_article.ex). The model is a stub: no test
  # reaches a provider.
  use Brando.LiveCase

  alias Brando.SyncTest

  @suggestion "[data-testid=field-ai-suggestion]"

  setup %{current_user: user} do
    Brando.AIStub.configure()

    {:ok, article} =
      SyncTest.create_article(
        %{title: "Fjordhuset", slug: "fjordhuset", subtitle: "Et hus", language: "no", status: "draft", year: 2020},
        user
      )

    %{article: article}
  end

  defp open(conn, article) do
    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}", "article_form")
    view
  end

  defp subtitle(view), do: view |> render() |> form_params("#article_form_form") |> get_in(["article", "subtitle"])

  defp run(view, action),
    do: view |> element("button[phx-click='run_field_action'][phx-value-action='#{action}']") |> render_click()

  defp replies(text) do
    test = self()

    Brando.AIStub.reply(fn prompt ->
      send(test, {:prompt, prompt})
      text
    end)
  end

  test "offers the field's actions in a menu beside its label", %{conn: conn, article: article} do
    view = open(conn, article)

    assert has_element?(view, "[data-testid=field-ai-menu]")
    assert has_element?(view, "button[phx-value-field='subtitle'][phx-value-action='summarize']", "Summarize the article")
    # Without a label, the action's name
    assert has_element?(view, "button[phx-value-field='subtitle'][phx-value-action='shorten']", "Shorten")
    # Only the field that declares actions has them
    refute has_element?(view, "button[phx-click='run_field_action'][phx-value-field='title']")
  end

  test "the reply is a suggestion until accepted, edited first if the editor wants", %{conn: conn, article: article} do
    view = open(conn, article)
    replies(~s("A plain summary of the house"))

    run(view, "summarize")
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='ready']")

    # The prompt: the instruction, its constraints, the entry's language and
    # the fields it reads, as the form has them
    assert_received {:prompt, prompt}
    assert prompt =~ "Summarize the article for a listing."
    assert prompt =~ "Write in Norsk."
    assert prompt =~ "Tone: plain and factual."
    assert prompt =~ "Use at most 160 characters."
    assert prompt =~ "title: Fjordhuset"

    # Shown, without its quotes, and not written into the field
    assert has_element?(view, "#{@suggestion} textarea.ai-proposal-field", "A plain summary of the house")
    assert subtitle(view) == "Et hus"

    view |> element("#{@suggestion} textarea") |> render_blur(%{"value" => "A summary, edited"})
    view |> element("#{@suggestion} button", "Accept") |> render_click()
    settle(view)

    assert subtitle(view) == "A summary, edited"
    refute has_element?(view, "#{@suggestion} .ai-proposal")
  end

  test "reads the unsaved form", %{conn: conn, article: article} do
    view = open(conn, article)
    replies("Kortere")

    view |> form("#article_form_form") |> render_change(%{"article" => %{"subtitle" => "Et hus ved fjorden, ulagret"}})
    run(view, "shorten")
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='ready']")

    assert_received {:prompt, prompt}
    assert prompt =~ "subtitle: Et hus ved fjorden, ulagret"
  end

  test "a cleared required field reads as empty, as the editor sees it", %{conn: conn, article: article} do
    view = open(conn, article)
    replies("Made up")

    # The title is required: the changeset keeps its saved value
    view
    |> form("#article_form_form")
    |> render_change(%{"article" => %{"title" => ""}, "_target" => ["article", "title"]})

    run(view, "summarize")

    await_selector(view, "#{@suggestion} .ai-proposal[data-status='failed'] [role=alert]")
    refute_received {:prompt, _}
  end

  test "discarding the suggestion leaves the field as it was", %{conn: conn, article: article} do
    view = open(conn, article)
    replies("Something else")

    run(view, "shorten")
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='ready']")
    view |> element("#{@suggestion} button", "Discard") |> render_click()

    refute has_element?(view, "#{@suggestion} .ai-proposal")
    assert subtitle(view) == "Et hus"
  end

  test "an action with nothing to read says so, without asking the model", %{conn: conn, article: article} do
    view = open(conn, article)
    replies("Made up")

    view |> form("#article_form_form") |> render_change(%{"article" => %{"subtitle" => ""}})
    run(view, "shorten")

    await_selector(view, "#{@suggestion} .ai-proposal[data-status='failed'] [role=alert]")
    refute_received {:prompt, _}
  end

  test "a failed request is shown with Try again", %{conn: conn, article: article} do
    view = open(conn, article)
    Brando.AIStub.reply(fn _prompt -> {:error, 500} end)

    run(view, "shorten")
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='failed']")

    assert has_element?(view, "#{@suggestion} button[phx-click='run_field_action'][phx-value-action='shorten']")
    assert subtitle(view) == "Et hus"
  end

  # A reply that takes a while, so a test can act while it runs.
  defp replies_slowly(text) do
    Brando.AIStub.reply(fn prompt ->
      Process.sleep(300)
      if prompt =~ "Shorten", do: "Shorter", else: text
    end)
  end

  test "cancelling a running request closes the suggestion, and its late end is ignored", %{conn: conn, article: article} do
    view = open(conn, article)
    replies_slowly("Too late")

    run(view, "summarize")
    assert has_element?(view, "#{@suggestion} .ai-proposal[data-status='running']")
    view |> element("#{@suggestion} button", "Cancel") |> render_click()

    Process.sleep(400)
    settle(view)
    assert Process.alive?(view.pid)
    refute has_element?(view, "#{@suggestion} .ai-proposal")
    assert subtitle(view) == "Et hus"
  end

  test "choosing another action while one runs shows only the last", %{conn: conn, article: article} do
    view = open(conn, article)
    replies_slowly("A summary")

    run(view, "summarize")
    run(view, "shorten")
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='ready']")
    Process.sleep(400)
    settle(view)

    assert has_element?(view, "#{@suggestion} .ai-proposal[data-status='ready'] .field-ai-action-name", "Shorten")
    assert has_element?(view, "#{@suggestion} textarea", "Shorter")
    refute has_element?(view, "#{@suggestion} [role=alert]")
  end

  test "a request with nothing to read, chosen while another runs, says why", %{conn: conn, article: article} do
    view = open(conn, article)
    replies_slowly("A summary")

    run(view, "summarize")
    view |> form("#article_form_form") |> render_change(%{"article" => %{"subtitle" => ""}})
    run(view, "shorten")
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='failed']")
    Process.sleep(400)
    settle(view)

    assert has_element?(view, "#{@suggestion} [role=alert]", "The fields this action reads are empty")
  end

  test "Accept asks first when the field changed since the action ran", %{conn: conn, article: article} do
    view = open(conn, article)
    replies("Shorter")

    run(view, "shorten")
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='ready']")

    # Another editor's change arrives, or this editor types in the field
    view |> form("#article_form_form") |> render_change(%{"article" => %{"subtitle" => "Et hus, endret"}})
    view |> element("#{@suggestion} button", "Accept") |> render_click()
    settle(view)

    assert has_element?(view, "#{@suggestion} [data-testid=field-ai-conflict]")
    assert subtitle(view) == "Et hus, endret"

    view |> element("#{@suggestion} button", "Replace") |> render_click()
    settle(view)

    assert subtitle(view) == "Shorter"
    refute has_element?(view, "#{@suggestion} .ai-proposal")
  end

  # An article with one block whose text ref, `body`, holds `text`
  defp article_with_text_block(user, text) do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    {:ok, article} =
      SyncTest.create_article(
        %{title: "Lang", slug: "lang", subtitle: "Et hus", language: "no", status: "draft", year: 2020},
        user
      )

    ref_uid = Brando.Utils.generate_uid()

    block =
      %Brando.Content.Block{}
      |> Brando.Content.Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "creator_id" => user.id,
          "source" => to_string(SyncTest.Article.Blocks),
          "refs" => [
            %{"uid" => ref_uid, "name" => "body", "data" => %{"type" => "text", "data" => %{"text" => text}}}
          ]
        },
        user
      )
      |> Brando.Repo.insert!()

    struct(SyncTest.Article.Blocks, %{entry_id: article.id, block_id: block.id, sequence: 0}) |> Brando.Repo.insert!()
    {article, ref_uid}
  end

  test "gives the model at most the context's length of block text", %{conn: conn, current_user: user} do
    {article, _ref_uid} = article_with_text_block(user, String.duplicate("ord ", 2_000))

    view = open(conn, article)
    await_selector(view, "#article_form-blocks-blocks-wrapper")
    replies("Kort")

    run(view, "summarize")
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='ready']")

    assert_received {:prompt, prompt}
    [_, blocks] = Regex.run(~r/^blocks: (.*)$/m, prompt)
    assert blocks =~ "ord ord"
    assert String.length(blocks) <= Brando.AI.Context.block_text_length()
  end

  describe "Write with AI in block text" do
    defp write_with_ai(view, ref_uid) do
      # As the editor's hook sends it, to the block that owns the text (its
      # form's target)
      [cid | _] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("form:has(#block-#{ref_uid}-rich-text)")
        |> LazyHTML.attribute("phx-target")
        |> Enum.reverse()

      view
      |> with_target(cid)
      |> render_hook("tiptap_ai_generate", %{
        "ref_name" => "body",
        "tiptap_id" => "block-#{ref_uid}-rich-text",
        "request_id" => "request-1",
        "mode" => "shorten",
        "instruction" => "",
        "selection" => "Et langt avsnitt om huset."
      })
    end

    test "is on whenever AI is configured, and its reply is a suggestion for the editor",
         %{conn: conn, current_user: user} do
      {article, ref_uid} = article_with_text_block(user, "<p>Et langt avsnitt om huset.</p>")
      view = open(conn, article)
      await_selector(view, "#block-#{ref_uid}-rich-text")
      replies("Et kort avsnitt.")

      assert has_element?(view, "#block-#{ref_uid}-rich-text[data-tiptap-ai='true']")

      write_with_ai(view, ref_uid)
      event = "b:tiptap:ai:block-#{ref_uid}-rich-text"

      assert_push_event(view, ^event, %{text: "Et kort avsnitt.", request_id: "request-1"})
      assert_received {:prompt, prompt}
      assert prompt =~ "Shorten the passage"
      assert prompt =~ "Passage:\nEt langt avsnitt om huset."
      # The editor shows it for review: the block's text is as it was
      assert has_element?(
               view,
               "#block-#{ref_uid}-rich-text input.tiptap-text[value='<p>Et langt avsnitt om huset.</p>']"
             )
    end

    test "the block_text site prompt adds the site's instructions", %{conn: conn, current_user: user} do
      put_test_env(
        Brando.AI,
        Keyword.put(Application.get_env(:brando, Brando.AI), :fields, block_text: [prompt: "Skriv enkelt."])
      )

      {article, ref_uid} = article_with_text_block(user, "<p>Et avsnitt.</p>")
      view = open(conn, article)
      await_selector(view, "#block-#{ref_uid}-rich-text")
      replies("Kort.")

      write_with_ai(view, ref_uid)
      event = "b:tiptap:ai:block-#{ref_uid}-rich-text"

      assert_push_event(view, ^event, %{text: "Kort."})
      assert_received {:prompt, prompt}
      assert prompt =~ ~r/\ASkriv enkelt\.\n\nShorten the passage/
    end

    test "is off with write_with_ai: false in the block_text site prompt", %{conn: conn, current_user: user} do
      put_test_env(
        Brando.AI,
        Keyword.put(Application.get_env(:brando, Brando.AI), :fields, block_text: [write_with_ai: false])
      )

      {article, ref_uid} = article_with_text_block(user, "<p>Et avsnitt.</p>")
      view = open(conn, article)
      await_selector(view, "#block-#{ref_uid}-rich-text")
      replies("Kort.")

      assert has_element?(view, "#block-#{ref_uid}-rich-text[data-tiptap-ai='false']")

      write_with_ai(view, ref_uid)
      event = "b:tiptap:ai:block-#{ref_uid}-rich-text"
      assert_push_event(view, ^event, %{error: true})
      refute_received {:prompt, _}
    end
  end

  describe "the Meta drawer" do
    # A page's meta fields take their Generate from the site prompts in
    # `trait :meta, ai:` (Brando.Pages.Page)
    setup %{current_user: user} do
      page = Factory.insert(:page, creator: user, title: "Om oss", uri: "om-oss", language: "no", meta_title: "Gammel")
      %{page: page}
    end

    defp meta_title(view), do: view |> render() |> form_params("#page_form_form") |> get_in(["page", "meta_title"])

    test "Generate suggests a meta title, written only when accepted", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      replies(~s("Om oss – Brando"))

      assert has_element?(view, "button[phx-value-field='meta_title'][phx-value-action='generate']", "Generate")
      refute has_element?(view, "button[phx-click='ai_generate_input']")

      run_meta(view, "meta_title")
      await_selector(view, "#page_meta_title-ai-actions .ai-proposal[data-status='ready']")

      assert_received {:prompt, prompt}
      assert prompt =~ "Write an SEO title tag"
      assert prompt =~ "title: Om oss"
      assert has_element?(view, "#page_meta_title-ai-actions textarea", "Om oss – Brando")
      assert meta_title(view) == "Gammel"

      view |> element("#page_meta_title-ai-actions button", "Accept") |> render_click()
      settle(view)

      assert meta_title(view) == "Om oss – Brando"
    end

    test "reads a cleared field as empty", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      replies("En tittel")

      view |> form("#page_form_form") |> render_change(%{"page" => %{"title" => ""}, "_target" => ["page", "title"]})
      run_meta(view, "meta_title")
      await_selector(view, "#page_meta_title-ai-actions .ai-proposal[data-status='ready']")

      assert_received {:prompt, prompt}
      assert prompt =~ "language: no"
      refute prompt =~ "Om oss"
    end

    defp run_meta(view, field) do
      view
      |> element("button[phx-click='run_field_action'][phx-value-field='#{field}'][phx-value-action='generate']")
      |> render_click()
    end
  end

  describe "a read-only field" do
    defp open_no_blocks(conn, article) do
      {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/no-blocks", "article_form")
      view
    end

    test "offers no actions to whom it is read-only", %{article: article} do
      admin = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
      view = open_no_blocks(log_in_user(build_conn(), admin), article)

      refute has_element?(view, "button[phx-click='run_field_action']")
    end

    test "offers them to a superuser, for whom it is not read-only", %{conn: conn, article: article} do
      view = open_no_blocks(conn, article)
      assert has_element?(view, "button[phx-click='run_field_action'][phx-value-field='subtitle']")
    end

    test "is not written by an Accept that reaches the form anyway", %{article: article} do
      admin = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
      view = open_no_blocks(log_in_user(build_conn(), admin), article)

      Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form,
        id: "article_form",
        event: "accept_field_action",
        field_name: "article[subtitle]",
        field: :subtitle,
        text: "Written anyway",
        original: "Et hus",
        replace: true
      )

      settle(view)
      assert subtitle(view) == "Et hus"
    end
  end

  test "without AI configured, no actions are offered", %{conn: conn, article: article} do
    Application.delete_env(:brando, Brando.AI)
    view = open(conn, article)

    refute has_element?(view, "button[phx-click='run_field_action']")
    refute has_element?(view, @suggestion)
  end
end
