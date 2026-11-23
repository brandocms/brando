defmodule BrandoAdmin.FormCancelledSaveTest do
  # brandocms/brando#3886: Postgres cancels one of two transactions that wait
  # for each other. When it is an editor's save (against a release apply
  # moving values in the same blocks), the form stays open with what was
  # typed, says so, and the next save writes it.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias BrandoAdmin.Components.Form

  setup %{conn: conn, current_user: user} do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
    Phoenix.PubSub.subscribe(Brando.pubsub(), "user:#{user.id}")
    {:ok, conn: conn, page: Factory.insert(:page, title: "Om oss")}
  end

  # The `table` cancels each `write` (UPDATE, INSERT) as Postgres cancels a
  # deadlock's victim, until `allow_saves!/1`
  defp cancel_saves!(write \\ "UPDATE", table \\ "pages") do
    Repo.query!("""
    CREATE FUNCTION cancel_save() RETURNS trigger AS $$
    BEGIN RAISE EXCEPTION 'deadlock detected' USING ERRCODE = '40P01'; END $$ LANGUAGE plpgsql
    """)

    Repo.query!("CREATE TRIGGER cancel_save BEFORE #{write} ON #{table} FOR EACH ROW EXECUTE FUNCTION cancel_save()")
  end

  defp allow_saves!(table \\ "pages"), do: Repo.query!("DROP TRIGGER cancel_save ON #{table}")

  # The toast that asks to save again; a refusal is an error
  defp assert_try_again_toast do
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{level: :error, type: :notification}}, 2_000
  end

  defp open(conn, page) do
    tab = %{"brando_tab" => "cancelled", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
    {view, _} = conn |> put_connect_params(tab) |> live_form("/admin/pages/update/#{page.id}")
    await_editing_tab(view)

    params = view |> render() |> form_params("#page_form_form") |> put_in(["page", "title"], "Typed")
    view |> element("#page_form_form") |> render_change(Map.put(params, "_target", ["page", "title"]))
    view
  end

  defp await_editing_tab(view, tries \\ 100) do
    cond do
      form_assigns(view).tab_editing? -> :ok
      tries == 0 -> flunk("the tab never came to edit")
      true -> Process.sleep(20) && await_editing_tab(view, tries - 1)
    end
  end

  defp form_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Form and &1.id == "page_form")).assigns
  end

  defp shown_title(view), do: view |> render() |> form_params("#page_form_form") |> get_in(["page", "title"])

  # What the browser sends: the first submit asks for the form (`b:submit`),
  # the second saves once the blocks arrive
  defp save(view) do
    params = view |> render() |> form_params("#page_form_form")
    view |> element("#page_form_form") |> render_submit(params)
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> element("#page_form_form") |> render_submit(params)
  end

  defp saved_title(page, title, tries \\ 100) do
    case Repo.get!(Brando.Pages.Page, page.id).title do
      ^title -> title
      other when tries == 0 -> other
      _ -> Process.sleep(20) && saved_title(page, title, tries - 1)
    end
  end

  test "a save Postgres cancels keeps the form and what was typed, and saving again writes it", %{
    conn: conn,
    page: page
  } do
    view = open(conn, page)
    cancel_saves!()

    save(view)

    assert_try_again_toast()
    assert Process.alive?(view.pid)
    refute form_assigns(view).processing
    assert shown_title(view) == "Typed"
    assert Repo.get!(Brando.Pages.Page, page.id).title == "Om oss"

    allow_saves!()
    save(view)
    assert saved_title(page, "Typed") == "Typed"
  end

  # Without group authorization the steps after the insert (identifier,
  # revision, Activity) are written apart from it unless the save is one
  # transaction: a cancel there would leave the entry saved while the form
  # says nothing was, and saving again would add a second one.
  test "a new entry's save Postgres cancels after its insert writes nothing, and saving again writes one", %{
    conn: conn
  } do
    {view, _} = live_form(conn, "/admin/pages/create")
    params = %{"page" => %{"title" => "Fresh", "uri" => "fresh", "template" => "default.html", "language" => "en"}}
    cancel_saves!("INSERT", "content_identifiers")

    save_new(view, params)

    assert_try_again_toast()
    refute form_assigns(view).entry.id
    assert fresh_pages() == 0

    allow_saves!("content_identifiers")
    save_new(view, params)
    assert await_fresh_pages() == 1
  end

  defp save_new(view, params) do
    view |> form("#page_form_form", params) |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#page_form_form", params) |> render_submit()
  end

  defp fresh_pages, do: Repo.aggregate(from(p in Brando.Pages.Page, where: p.uri == "fresh"), :count)

  defp await_fresh_pages(tries \\ 100) do
    case fresh_pages() do
      0 when tries > 0 -> Process.sleep(20) && await_fresh_pages(tries - 1)
      count -> count
    end
  end
end
