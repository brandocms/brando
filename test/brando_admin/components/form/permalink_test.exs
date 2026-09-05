defmodule BrandoAdmin.Components.Form.PermalinkTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Sites.Redirects
  alias BrandoAdmin.Components.Form
  alias Phoenix.Component

  setup do
    Brando.Cache.SEO.set()
    user = Brando.Factory.insert(:random_user)
    page = Brando.Factory.insert(:page, uri: "old-permalink", creator: user, has_url: true)

    socket =
      %Phoenix.LiveView.Socket{}
      |> Component.assign(%{
        id: "page_form",
        schema: Brando.Pages.Page,
        singular: "page",
        context: Brando.Pages,
        entry: page,
        entry_id: page.id,
        current_user: user,
        form_blueprint: Brando.Pages.Page.__form__(:default),
        form: Component.to_form(Ecto.Changeset.change(page)),
        has_blocks?: false,
        has_transformers?: false,
        all_transformers_received?: true,
        transformer_changesets: %{},
        processing: true,
        pending_permalink_redirect: nil,
        permalink_redirect_error: nil,
        save_redirect_target: :self,
        live_preview_active?: false,
        fields_demanding_live_preview_reassign: []
      })

    {:ok, socket: socket, page: page}
  end

  test "saves first, then creates only the server-side proposal on confirmation", %{socket: socket, page: page} do
    {:noreply, socket} = Form.handle_event("save", %{"page" => %{"uri" => "new-permalink"}}, socket)
    assert Brando.Repo.get!(Brando.Pages.Page, page.id).uri == "new-permalink"
    assert socket.assigns.pending_permalink_redirect.redirect.from == "/en/old-permalink"
    refute socket.assigns.processing
    assert Redirects.test_redirect(["en", "old-permalink"], "en") == {:error, {:redirects, :no_match}}

    {:noreply, socket} = Form.handle_event("create_permalink_redirect", %{"to" => "/untrusted"}, socket)
    assert Redirects.test_redirect(["en", "old-permalink"], "en") == {:ok, {:redirect, {"/en/new-permalink", 301}}}
    assert socket.assigns.pending_permalink_redirect == nil
    assert socket.assigns.entry.uri == "new-permalink"
    refute socket.assigns.processing

    assert {:noreply, ^socket} = Form.handle_event("create_permalink_redirect", %{}, socket)
  end

  test "dismissal keeps the saved entry and allows another URL change", %{socket: socket} do
    {:noreply, socket} = Form.handle_event("save", %{"page" => %{"uri" => "second-permalink"}}, socket)
    {:noreply, socket} = Form.handle_event("skip_permalink_redirect", %{}, socket)
    assert socket.assigns.pending_permalink_redirect == nil
    assert socket.assigns.entry.uri == "second-permalink"
    assert Redirects.test_redirect(["en", "old-permalink"], "en") == {:error, {:redirects, :no_match}}

    {:noreply, socket} = Form.handle_event("save", %{"page" => %{"uri" => "third-permalink"}}, socket)
    assert socket.assigns.pending_permalink_redirect.redirect.from == "/en/second-permalink"
  end

  test "failed redirect creation keeps the prompt available for retry or dismissal", %{socket: socket} do
    {:noreply, socket} = Form.handle_event("save", %{"page" => %{"uri" => "new-permalink"}}, socket)
    pending = Map.update!(socket.assigns.pending_permalink_redirect, :redirect, &Map.put(&1, :language, "no"))
    socket = Component.assign(socket, :pending_permalink_redirect, pending)
    {:noreply, socket} = Form.handle_event("create_permalink_redirect", %{}, socket)
    assert socket.assigns.permalink_redirect_error =~ "entry was saved"
    assert socket.assigns.pending_permalink_redirect
    assert {:noreply, ^socket} = Form.handle_event("save", %{"page" => %{"uri" => "ignored"}}, socket)
    {:noreply, socket} = Form.handle_event("skip_permalink_redirect", %{}, socket)
    refute socket.assigns.pending_permalink_redirect
    refute socket.assigns.permalink_redirect_error
  end
end
