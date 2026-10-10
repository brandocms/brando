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

    # The summary reads the blocks: it runs once the block field answered
    run(view, "summarize")
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='running']")
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
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='running']")
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
    await_selector(view, "#{@suggestion} .ai-proposal[data-status='running']")
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
  # `write_with_ai:` is the module's Write with AI setting
  defp article_with_text_block(user, text, write_with_ai \\ false) do
    {article, ref_uid, _module} = text_block_article(user, text, write_with_ai)
    {article, ref_uid}
  end

  defp text_block_article(user, text, write_with_ai) do
    module = text_module(user, write_with_ai)

    {:ok, article} =
      SyncTest.create_article(
        %{title: "Lang", slug: "lang", subtitle: "Et hus", language: "no", status: "draft", year: 2020},
        user
      )

    {_block_uid, ref_uid} = put_text_block(user, article, module, SyncTest.Article.Blocks, text)
    {article, ref_uid, module}
  end

  defp text_module(user, write_with_ai \\ false) do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          write_with_ai: write_with_ai,
          name: %{"en" => "Text"},
          namespace: %{"en" => "Content"},
          help_text: %{"en" => "Text"},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    module
  end

  # A saved block of `module` in the article's block field `join` (its
  # join schema), its `body` holding `text`. Saved as a fixture is: without
  # rendering the field's `rendered_` column.
  defp put_text_block(user, article, module, join, text) do
    block_uid = Brando.Utils.generate_uid()
    ref_uid = Brando.Utils.generate_uid()

    block =
      %Brando.Content.Block{}
      |> Brando.Content.Block.recursive_block_changeset(
        %{
          "uid" => block_uid,
          "type" => "module",
          "module_id" => module.id,
          "creator_id" => user.id,
          "source" => to_string(join),
          "refs" => [
            %{"uid" => ref_uid, "name" => "body", "data" => %{"type" => "text", "data" => %{"text" => text}}}
          ]
        },
        user
      )
      |> Brando.Repo.insert!()

    struct(join, %{entry_id: article.id, block_id: block.id, sequence: 0}) |> Brando.Repo.insert!()
    {block_uid, ref_uid}
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

  describe "an action that reads block fields" do
    # `form :notes`: the article's `blocks` and `notes` block fields; the
    # subtitle's `outline` reads `notes` by name, `everything` reads `:blocks`
    setup %{current_user: user, article: article} do
      module = text_module(user)
      {main_uid, _} = put_text_block(user, article, module, SyncTest.Article.Blocks, "<p>Hovedtekst</p>")
      {notes_uid, _} = put_text_block(user, article, module, SyncTest.Article.Notes, "<p>Lagret notat</p>")
      %{main_uid: main_uid, notes_uid: notes_uid}
    end

    defp open_notes(conn, article, block_uids) do
      {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/notes", "article_form")
      Enum.each(block_uids, &await_selector(view, "#entry_block_form-#{&1}"))
      view
    end

    # As the block's text editor sends it, without saving the entry
    defp edit_block_text(view, block_uid, html) do
      selector = "#entry_block_form-#{block_uid}"
      path = ["entry_block", "block", "refs", "0", "data", "data", "text"]
      params = view |> render() |> form_params(selector) |> put_in(path, html) |> Map.put("_target", path)
      view |> element(selector) |> render_change(params)
    end

    test "a block field named in from: is read as the editor has it, alone",
         %{conn: conn, article: article, main_uid: main_uid, notes_uid: notes_uid} do
      view = open_notes(conn, article, [main_uid, notes_uid])
      replies("Disposisjon")

      edit_block_text(view, notes_uid, "<p>Ulagret notat</p>")
      run(view, "outline")
      await_selector(view, "#{@suggestion} .ai-proposal[data-status='ready']")

      assert_received {:prompt, prompt}
      assert prompt =~ "notes: Ulagret notat"
      refute prompt =~ "Lagret notat"
      refute prompt =~ "Hovedtekst"
    end

    test ":blocks reads every block field as the editor has it",
         %{conn: conn, article: article, main_uid: main_uid, notes_uid: notes_uid} do
      view = open_notes(conn, article, [main_uid, notes_uid])
      replies("Sammendrag")

      edit_block_text(view, main_uid, "<p>Ulagret hovedtekst</p>")
      edit_block_text(view, notes_uid, "<p>Ulagret notat</p>")
      run(view, "everything")
      await_selector(view, "#{@suggestion} .ai-proposal[data-status='ready']")

      assert_received {:prompt, prompt}
      assert prompt =~ "Ulagret hovedtekst"
      assert prompt =~ "Ulagret notat"
      refute prompt =~ "Lagret notat"
    end

    test "an action chosen while another waits for its blocks is the one that runs",
         %{conn: conn, article: article, main_uid: main_uid, notes_uid: notes_uid} do
      view = open_notes(conn, article, [main_uid, notes_uid])
      replies("Svar")

      # The outline asks the notes field for its blocks; the editor picks
      # Shorten, which reads none, before they arrive. Both clicks are in the
      # LiveView's mailbox ahead of the field's answer.
      [cid] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("button[phx-click='run_field_action'][phx-value-action='outline']")
        |> LazyHTML.attribute("phx-target")

      cid = String.to_integer(cid)
      :sys.suspend(view.pid)
      click(view, cid, "outline", 1_000_001)
      click(view, cid, "shorten", 1_000_002)
      :sys.resume(view.pid)

      assert_receive {:prompt, prompt}, 2_000
      assert prompt =~ "Shorten the subtitle."
      refute_receive {:prompt, _}, 500
    end

    defp click(view, cid, action, ref),
      do: push_raw(view, cid, "click", "run_field_action", %{"field" => "subtitle", "action" => action}, ref)

    # An event as the browser sends it, straight to the LiveView: Phoenix's
    # test client waits for each one to be handled before sending the next
    defp push_raw(view, cid, type, event, value, ref) do
      {_ref, topic, proxy} = view.proxy
      %{join_ref: join_ref} = :sys.get_state(proxy)

      send(view.pid, %Phoenix.Socket.Message{
        join_ref: join_ref,
        topic: topic,
        event: "event",
        ref: to_string(ref),
        payload: %{"type" => type, "event" => event, "value" => value, "cid" => cid}
      })
    end

    @generate %{
      "field_key" => "subtitle",
      "field_name" => "article[subtitle]",
      "tiptap_id" => "article_subtitle-rich-text",
      "request_id" => "request-1",
      "mode" => "rewrite",
      "instruction" => "",
      "selection" => "Et hus."
    }

    # The block fields answer only once the entry's edit session does: held
    # past the wait, the request is given up on before they answer
    defp hold_blocks_past_the_wait(article, act) do
      put_test_env(:ai_blocks_collect_ms, 50)
      session = Brando.EditSession.whereis(Brando.EditSession.ref_for(article))
      :sys.suspend(session)
      act.()
      Process.sleep(150)
      :sys.resume(session)
    end

    test "an action whose blocks do not come in time says so, without asking the model",
         %{conn: conn, article: article, main_uid: main_uid, notes_uid: notes_uid} do
      view = open_notes(conn, article, [main_uid, notes_uid])
      replies("Disposisjon")

      hold_blocks_past_the_wait(article, fn -> run(view, "outline") end)

      await_selector(view, "#{@suggestion} .ai-proposal[data-status='failed'] [role=alert]")
      assert has_element?(view, "#{@suggestion} button[phx-click='run_field_action'][phx-value-action='outline']")
      refute_receive {:prompt, _}, 300
    end

    test "Write with AI whose blocks do not come in time ends in an error, without asking the model",
         %{conn: conn, article: article, main_uid: main_uid, notes_uid: notes_uid} do
      view = open_notes(conn, article, [main_uid, notes_uid])
      replies("Et forslag.")
      cid = cid_of(view, "#article_form_form")

      hold_blocks_past_the_wait(article, fn ->
        view |> with_target(cid) |> render_hook("tiptap_ai_generate", @generate)
      end)

      event = "b:tiptap:ai:article_subtitle-rich-text"
      assert_push_event(view, ^event, %{error: true, request_id: "request-1"})
      refute_receive {:prompt, _}, 300
    end

    test "Write with AI cancelled while it waits for its blocks asks the model nothing",
         %{conn: conn, article: article, main_uid: main_uid, notes_uid: notes_uid} do
      view = open_notes(conn, article, [main_uid, notes_uid])
      replies("Et forslag.")
      cid = cid_of(view, "#article_form_form")

      # Both in the LiveView's mailbox ahead of the block field's answer
      :sys.suspend(view.pid)
      push_raw(view, cid, "hook", "tiptap_ai_generate", @generate, 1_000_001)

      push_raw(
        view,
        cid,
        "hook",
        "tiptap_ai_cancel",
        %{"tiptap_id" => "article_subtitle-rich-text", "request_id" => "request-1"},
        1_000_002
      )

      :sys.resume(view.pid)

      settle(view)
      refute_receive {:prompt, _}, 500
    end

    test "Write with AI reads a block field named in its from: as the editor has it",
         %{conn: conn, article: article, main_uid: main_uid, notes_uid: notes_uid} do
      view = open_notes(conn, article, [main_uid, notes_uid])
      replies("Et forslag.")

      edit_block_text(view, notes_uid, "<p>Ulagret notat</p>")

      view
      |> with_target(cid_of(view, "#article_form_form"))
      |> render_hook("tiptap_ai_generate", %{
        "field_key" => "subtitle",
        "field_name" => "article[subtitle]",
        "tiptap_id" => "article_subtitle-rich-text",
        "request_id" => "request-1",
        "mode" => "rewrite",
        "instruction" => "",
        "selection" => "Et hus."
      })

      event = "b:tiptap:ai:article_subtitle-rich-text"
      assert_push_event(view, ^event, %{text: "Et forslag.", request_id: "request-1"})
      assert_received {:prompt, prompt}
      assert prompt =~ "notes: Ulagret notat"
      refute prompt =~ "Hovedtekst"
    end
  end

  describe "Write with AI in block text" do
    # The block component (its form's target) that owns the text
    defp block_cids(view, ref_uid) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("form:has(#block-#{ref_uid}-rich-text)")
      |> LazyHTML.attribute("phx-target")
      |> Enum.reverse()
    end

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

    test "is off in a module that does not turn it on, and the server refuses a request",
         %{conn: conn, current_user: user} do
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

    test "is on in a module that turns it on, and its reply is a suggestion for the editor",
         %{conn: conn, current_user: user} do
      {article, ref_uid} = article_with_text_block(user, "<p>Et langt avsnitt om huset.</p>", true)
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

    test "follows the module's switch in an open editor, on and off, without remounting the block",
         %{conn: conn, current_user: user} do
      {article, ref_uid, module} = text_block_article(user, "<p>Et avsnitt.</p>", false)
      view = open(conn, article)
      selector = "#block-#{ref_uid}-rich-text"
      await_selector(view, selector)
      assert has_element?(view, "#{selector}[data-tiptap-ai='false']")
      # The block keeps its component: it is updated, not remounted
      [cid | _] = block_cids(view, ref_uid)

      {:ok, module} = Brando.Content.update_module(module, %{write_with_ai: true}, user)
      await_selector(view, "#{selector}[data-tiptap-ai='true']")
      assert [^cid | _] = block_cids(view, ref_uid)

      {:ok, _module} = Brando.Content.update_module(module, %{write_with_ai: false}, user)
      await_selector(view, "#{selector}[data-tiptap-ai='false']")
      assert [^cid | _] = block_cids(view, ref_uid)
    end

    test "the block_text site prompt adds the site's instructions", %{conn: conn, current_user: user} do
      put_test_env(
        Brando.AI,
        Keyword.put(Application.get_env(:brando, Brando.AI), :prompts, block_text: [prompt: "Skriv enkelt."])
      )

      {article, ref_uid} = article_with_text_block(user, "<p>Et avsnitt.</p>", true)
      view = open(conn, article)
      await_selector(view, "#block-#{ref_uid}-rich-text")
      replies("Kort.")

      write_with_ai(view, ref_uid)
      event = "b:tiptap:ai:block-#{ref_uid}-rich-text"

      assert_push_event(view, ^event, %{text: "Kort."})
      assert_received {:prompt, prompt}
      assert prompt =~ ~r/\ASkriv enkelt\.\n\nShorten the passage/
    end

    test "is off with write_with_ai: false in the block_text site prompt, even where a module turns it on",
         %{conn: conn, current_user: user} do
      put_test_env(
        Brando.AI,
        Keyword.put(Application.get_env(:brando, Brando.AI), :prompts, block_text: [write_with_ai: false])
      )

      {article, ref_uid} = article_with_text_block(user, "<p>Et avsnitt.</p>", true)
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

  describe "a meta field that is also an input in a tab" do
    # Brando.MetaDrawerTest.ActionsArticle's `form :visible`: the meta
    # description in a tab, with its own action, and in the Meta drawer, with
    # that action and the site prompt's Generate
    setup %{current_user: user} do
      page = Factory.insert(:page, creator: user, title: "Om oss", uri: "om-oss-meta", language: "no")
      %{page: page}
    end

    test "has a suggestion panel in each place, each answering for itself", %{conn: conn, page: page} do
      # The meta description's own input is in the form twice, in the tab and
      # in the drawer, as it always was; LiveView itself refuses a component
      # rendered twice under one id, which is what this is about.
      {:ok, view, _html} = live(conn, "/admin/meta-articles/update/#{page.id}", on_error: [duplicate_id: :ignore])
      render_async(view, 5_000)
      await_selector(view, "#actions_article_form_form input")
      replies("En kortere beskrivelse")

      tab = "#actions_article_meta_description-ai-actions"
      drawer = "#actions_article_meta_description-meta-ai-actions"
      assert has_element?(view, tab)
      assert has_element?(view, drawer)

      view
      |> element("button[phx-click='run_field_action'][phx-value-action='generate'][phx-value-panel$='-meta-ai-actions']")
      |> render_click()

      await_selector(view, "#{drawer} .ai-proposal[data-status='ready']")
      refute has_element?(view, "#{tab} .ai-proposal")

      view |> element("#{drawer} button", "Accept") |> render_click()
      settle(view)

      assert view
             |> render()
             |> form_params("#actions_article_form_form")
             |> get_in(["actions_article", "meta_description"]) ==
               "En kortere beskrivelse"

      refute has_element?(view, "#{drawer} .ai-proposal")
    end
  end

  describe "Write with AI in a rich text input" do
    setup %{current_user: user} do
      page = Factory.insert(:page, creator: user, title: "Om oss", uri: "om-oss-rich", language: "no")
      %{page: page}
    end

    test "starts with its write_with_ai: instructions and the fields they read, with its model",
         %{conn: conn, page: page} do
      {:ok, view, _html} = live(conn, "/admin/meta-articles/update/#{page.id}", on_error: [duplicate_id: :ignore])
      render_async(view, 5_000)
      await_selector(view, "#actions_article_form_form input")
      test = self()

      Brando.AI.Cassette.stub(fn request ->
        send(test, {:request, request})
        %{"text" => "Et forslag.", "usage" => %{"input_tokens" => 1, "output_tokens" => 1}}
      end)

      assert has_element?(view, "[data-tiptap-field='css_classes'][data-tiptap-ai='true']")

      view
      |> with_target(cid_of(view, "#actions_article_form_form"))
      |> render_hook("tiptap_ai_generate", %{
        "field_key" => "css_classes",
        "field_name" => "actions_article[css_classes]",
        "tiptap_id" => "actions_article_css_classes-rich-text",
        "request_id" => "request-1",
        "mode" => "rewrite",
        "instruction" => "",
        "selection" => "Et avsnitt."
      })

      event = "b:tiptap:ai:actions_article_css_classes-rich-text"
      assert_push_event(view, ^event, %{text: "Et forslag.", request_id: "request-1"})
      assert_received {:request, request}
      assert request["model"] == "openai:gpt-4o"
      prompt = Brando.AIStub.prompt(request)
      assert prompt =~ ~r/\AKeep the house style\.\n\nContext:\ntitle: Om oss\n\nRewrite the passage\./
    end

    test "is off in rich text without write_with_ai:, and the form refuses a request for it", %{conn: conn, page: page} do
      {:ok, view, _html} = live(conn, "/admin/meta-articles/update/#{page.id}", on_error: [duplicate_id: :ignore])
      render_async(view, 5_000)
      await_selector(view, "#actions_article_form_form input")
      replies("Et forslag.")

      assert has_element?(view, "[data-tiptap-field='template'][data-tiptap-ai='false']")

      view
      |> with_target(cid_of(view, "#actions_article_form_form"))
      |> render_hook("tiptap_ai_generate", %{
        "field_key" => "template",
        "field_name" => "actions_article[template]",
        "tiptap_id" => "actions_article_template-rich-text",
        "request_id" => "request-1",
        "mode" => "rewrite",
        "instruction" => "",
        "selection" => "Et avsnitt."
      })

      event = "b:tiptap:ai:actions_article_template-rich-text"
      assert_push_event(view, ^event, %{error: true, request_id: "request-1"})
      refute_received {:prompt, _}
    end
  end

  describe "the Meta drawer" do
    # A page's meta fields take their Generate from the site prompts in
    # `trait :meta, ai_prompts:` (Brando.Pages.Page)
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
      await_selector(view, "#page_meta_title-meta-ai-actions .ai-proposal[data-status='ready']")

      assert_received {:prompt, prompt}
      assert prompt =~ "Write an SEO title tag"
      assert prompt =~ "title: Om oss"
      assert has_element?(view, "#page_meta_title-meta-ai-actions textarea", "Om oss – Brando")
      assert meta_title(view) == "Gammel"

      view |> element("#page_meta_title-meta-ai-actions button", "Accept") |> render_click()
      settle(view)

      assert meta_title(view) == "Om oss – Brando"
    end

    test "sends the site prompt even when the fields it reads are empty, as ai: did", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      replies("En tittel")

      # The Page's meta title prompt reads title, blocks and language
      view
      |> form("#page_form_form")
      |> render_change(%{"page" => %{"title" => "", "language" => ""}, "_target" => ["page", "title"]})

      run_meta(view, "meta_title")
      await_selector(view, "#page_meta_title-meta-ai-actions .ai-proposal[data-status='ready']")
      assert_received {:prompt, prompt}
      assert prompt =~ "Write an SEO title tag"
    end

    test "reads a cleared field as empty", %{conn: conn, page: page} do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      replies("En tittel")

      view |> form("#page_form_form") |> render_change(%{"page" => %{"title" => ""}, "_target" => ["page", "title"]})
      run_meta(view, "meta_title")
      await_selector(view, "#page_meta_title-meta-ai-actions .ai-proposal[data-status='ready']")

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
