defmodule BrandoAdmin.TransformerLateUploadTest do
  # An image upload that lands after its card stopped waiting for it: the
  # card was removed, a second file was dropped on it, or a recovery copy
  # was restored over it. The file adds no row; before, the transformer
  # appended it as one.
  use Brando.LiveCase, async: true

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.SyncTest
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Transformer

  setup %{conn: conn, current_user: me} do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Rows",
          slug: "rows",
          language: "en",
          status: "published",
          items: [%{label: "A", sequence: 0}, %{label: "B", sequence: 1}]
        },
        me
      )

    params = %{"brando_tab" => "a", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
    {view, _} = conn |> put_connect_params(params) |> live_form("/admin/albums/update/#{article.id}", "album_form")
    form = %{view: view, id: "album_form"}
    await(fn -> form_assigns(form).tab_editing? end)
    %{form: form, article: article}
  end

  defp components(%{view: view}) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    components
  end

  defp form_assigns(%{id: id} = form), do: Enum.find(components(form), &(&1.module == Form and &1.id == id)).assigns

  defp transformer(form), do: Enum.find(components(form), &(&1.module == Transformer)).assigns

  defp form_target(%{view: view, id: id}), do: with_target(view, cid_of(view, "##{id}-el"))

  defp transformer_target(%{view: view} = form),
    do: with_target(view, cid_of(view, "##{transformer(form).id}-uploader"))

  defp await(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("never came true")
      true -> Process.sleep(20) && await(fun, tries - 1)
    end
  end

  defp dom_id_of(form, label), do: Enum.find_value(transformer(form).items, &(shown(&1, :label) == label && &1.dom_id))

  defp shown(item, field), do: Map.merge(Map.new(Map.take(item.source, [field])), item.changes)[field]

  defp file(ref), do: %{"ref" => ref, "filename" => "#{ref}.jpg", "size" => 10, "kind" => "image"}

  defp replace(form, label, ref) do
    form
    |> transformer_target()
    |> render_hook("register_replacement", %{"dom_id" => dom_id_of(form, label), "file" => file(ref)})
  end

  # The sticky UploadManager hands a finished upload to the transformer
  defp deliver_upload(%{view: view} = form, ref, asset) do
    Phoenix.LiveView.send_update(view.pid, Transformer,
      id: transformer(form).id,
      event: "upload_complete",
      ref: ref,
      asset: asset
    )

    settle(view)
  end

  defp labels(form), do: Enum.map(transformer(form).items, &shown(&1, :label))

  defp image_ids(form), do: Enum.map(transformer(form).items, &shown(&1, :cover_id))

  defp latest_copy(article) do
    Repo.one(
      from d in Brando.Drafts.EntryDraft,
        where: d.entry_id == ^article.id and is_nil(d.resolved_at),
        order_by: [desc: d.id],
        limit: 1
    )
  end

  defp browser_form(%{view: view, id: id}) do
    view |> render() |> form_params("##{id}_form") |> Plug.Conn.Query.encode()
  end

  test "a card removed while its replacement uploads adds no row when the file lands", %{form: form} do
    replace(form, "B", "tf-removed")
    form |> transformer_target() |> render_hook("remove_entry", %{"dom_id" => dom_id_of(form, "B")})
    assert_push_event(form.view, "transformer:abort_upload", %{ref: "tf-removed"})

    deliver_upload(form, "tf-removed", Factory.insert(:image))
    assert labels(form) == ["A"]
  end

  test "a first replacement that lands after a second file was dropped on the card adds no row", %{form: form} do
    replace(form, "B", "tf-first")
    replace(form, "B", "tf-second")
    assert_push_event(form.view, "transformer:abort_upload", %{ref: "tf-first"})

    deliver_upload(form, "tf-first", Factory.insert(:image))
    assert labels(form) == ["A", "B"]

    second = Factory.insert(:image)
    deliver_upload(form, "tf-second", second)
    assert labels(form) == ["A", "B"]
    assert image_ids(form) == [nil, second.id]
  end

  test "an upload running when a recovery copy is restored adds no row when it lands",
       %{form: form, article: article} do
    form
    |> transformer_target()
    |> render_hook("update_field", %{"dom_id" => dom_id_of(form, "A"), "field" => "label", "value" => "A, edited"})

    params = %{"main" => browser_form(form), "blocks" => %{}, "generation" => 1, "request_id" => 1}
    form |> form_target() |> render_hook("draft_capture", params)
    await(fn -> latest_copy(article) != nil end)

    replace(form, "B", "tf-restored")
    form |> transformer_target() |> render_hook("register_batch", %{"files" => [file("tf-batch")]})
    assert labels(form) == ["A, edited", "B", nil]

    form |> form_target() |> render_hook("draft_restore", %{"id" => latest_copy(article).id})
    settle(form.view)
    await(fn -> labels(form) == ["A, edited", "B"] end)

    deliver_upload(form, "tf-restored", Factory.insert(:image))
    deliver_upload(form, "tf-batch", Factory.insert(:image))
    assert labels(form) == ["A, edited", "B"]
  end

  test "an upload to a new card still adds its row", %{form: form} do
    form |> transformer_target() |> render_hook("register_batch", %{"files" => [file("tf-new")]})
    image = Factory.insert(:image)
    deliver_upload(form, "tf-new", image)

    assert [_, _, _] = labels(form)
    assert image_ids(form) == [nil, nil, image.id]
  end
end
