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

  test "without AI configured, no actions are offered", %{conn: conn, article: article} do
    Application.delete_env(:brando, Brando.AI)
    view = open(conn, article)

    refute has_element?(view, "button[phx-click='run_field_action']")
    refute has_element?(view, @suggestion)
  end
end
