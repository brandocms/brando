defmodule BrandoAdmin.TransformerUnsavedRowsTest do
  # A row added to a transformer and not saved yet, through the real form: its
  # fields drawn once it is opened (with a listing) or as soon as it is added
  # (without one), typed in as the Transformer's hooks type, and saved.
  use Brando.LiveCase, async: true

  @moduletag :capture_log

  import Brando.Factory
  import Ecto.Query, only: [from: 2]

  alias Brando.SyncTest
  alias Brando.SyncTest.ArticleItem
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Transformer

  setup %{current_user: me} do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "Rows", slug: "rows", language: "en", status: "published", items: [%{label: "A", sequence: 0}]},
        me
      )

    %{article: article}
  end

  defp open(conn, article, form_name) do
    tab = %{"brando_tab" => "rows", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}

    {view, _} =
      conn
      |> put_connect_params(tab)
      |> live_form("/admin/articles/update/#{article.id}/#{form_name}", "article_form")

    await(fn -> form_assigns(view).tab_editing? end)
    %{view: view}
  end

  defp components(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    components
  end

  defp form_assigns(view), do: Enum.find(components(view), &(&1.module == Form and &1.id == "article_form")).assigns
  defp transformer(%{view: view}), do: Enum.find(components(view), &(&1.module == Transformer)).assigns

  defp transformer_target(%{view: view} = form),
    do: with_target(view, cid_of(view, "##{transformer(form).id}-uploader"))

  defp form_target(%{view: view}), do: with_target(view, cid_of(view, "#article_form-el"))

  defp await(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("never came true")
      true -> Process.sleep(20) && await(fun, tries - 1)
    end
  end

  defp new_dom_ids(form, fun) do
    before = Enum.map(transformer(form).items, & &1.dom_id)
    fun.()
    Enum.map(transformer(form).items, & &1.dom_id) -- before
  end

  defp add_row(form) do
    [dom_id] = new_dom_ids(form, fn -> form |> transformer_target() |> render_hook("add_entry", %{}) end)
    dom_id
  end

  defp set_field(form, dom_id, field, value) do
    form |> transformer_target() |> render_hook("update_field", %{"dom_id" => dom_id, "field" => field, "value" => value})
  end

  defp label_input(dom_id), do: "##{dom_id}_label"

  defp browser_form(%{view: view}) do
    view |> render() |> form_params("#article_form_form") |> Plug.Conn.Query.encode()
  end

  # "Save and continue editing" as the browser makes it: the first push
  # collects, the second answers `b:submit` with its token
  defp save(form) do
    form |> form_target() |> render_hook("save_form", %{"form" => browser_form(form), "stay" => true})
    assert_push_event(form.view, "b:submit", %{token: token}, 5_000)
    form |> form_target() |> render_hook("save_form", %{"form" => browser_form(form), "token" => token})
    settle(form.view)
  end

  defp rows(article) do
    Repo.all(from i in ArticleItem, where: i.article_id == ^article.id, order_by: i.sequence, select: {i.id, i.label})
  end

  describe "a row not saved yet, with a listing" do
    test "opens, and its fields show what it has", %{conn: conn, article: article} do
      form = open(conn, article, "transformer_rich_items")
      dom_id = add_row(form)
      set_field(form, dom_id, "label", "New")

      form |> transformer_target() |> render_hook("toggle_entry", %{"dom_id" => dom_id})

      assert has_element?(form.view, ~s{#{label_input(dom_id)}[value="New"]})
    end
  end

  describe "a row not saved yet, without a listing" do
    test "added by the Add button shows its default", %{conn: conn, article: article} do
      form = open(conn, article, "transformer_unlisted_items")
      dom_id = add_row(form)

      assert has_element?(form.view, ~s{#{label_input(dom_id)}[value="Untitled"]})
    end

    test "added by an upload shows its fields", %{conn: conn, article: article, current_user: me} do
      form = open(conn, article, "transformer_unlisted_items")
      image = insert(:image, creator_id: me.id)
      id = transformer(form).id

      [dom_id] =
        new_dom_ids(form, fn ->
          Phoenix.LiveView.send_update(form.view.pid, Transformer, id: id, event: "upload_complete", asset: image)
          render(form.view)
        end)

      assert has_element?(form.view, ~s{#{label_input(dom_id)}[value="Untitled"]})
    end

    test "keeps what was typed, and is inserted once", %{conn: conn, article: article} do
      form = open(conn, article, "transformer_unlisted_items")
      [{a, "A"}] = rows(article)
      dom_id = add_row(form)

      set_field(form, dom_id, "label", "Typed")
      assert has_element?(form.view, ~s{#{label_input(dom_id)}[value="Typed"]})

      save(form)
      assert [{^a, "A"}, {new, "Typed"}] = rows(article)
      assert has_element?(form.view, ~s{#{label_input(dom_id)}[value="Typed"]})

      save(form)
      assert rows(article) == [{a, "A"}, {new, "Typed"}]
    end
  end
end
