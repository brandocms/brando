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

  for target <- ["old-permalink", "reclaimed-permalink"] do
    test "removes the existing redirect on #{target} before the prompt, even when dismissed", %{socket: socket} do
      target = unquote(target)
      {:noreply, socket} = Form.handle_event("save", %{"page" => %{"uri" => "current-permalink"}}, socket)
      {:noreply, socket} = Form.handle_event("create_permalink_redirect", %{}, socket)

      if target == "reclaimed-permalink" do
        assert {:ok, _} =
                 Redirects.create_permalink_redirect(
                   %{from: "/en/#{target}", to: "/en/elsewhere", language: "en"},
                   :system
                 )
      end

      assert {:ok, {:redirect, _}} = Redirects.test_redirect(["en", target], "en")
      socket = Component.assign(socket, :save_redirect_target, :self)
      {:noreply, socket} = Form.handle_event("save", %{"page" => %{"uri" => target}}, socket)
      assert socket.assigns.pending_permalink_redirect.redirect.to == "/en/#{target}"
      assert Redirects.test_redirect(["en", target], "en") == {:error, {:redirects, :no_match}}

      {:noreply, socket} = Form.handle_event("skip_permalink_redirect", %{}, socket)
      assert socket.assigns.entry.uri == target
      assert Redirects.test_redirect(["en", target], "en") == {:error, {:redirects, :no_match}}
      assert Redirects.test_redirect(["en", "current-permalink"], "en") == {:error, {:redirects, :no_match}}
    end
  end

  test "cleanup uses the saved language while the proposal uses the previous language", %{socket: socket} do
    Brando.Repo.insert!(struct(Brando.Sites.SEO, language: :no))
    proposal = %{from: "/no/reclaimed", to: "/elsewhere", language: "no"}
    assert {:ok, _} = Redirects.create_permalink_redirect(proposal, :system)
    assert {:ok, _} = Redirects.create_permalink_redirect(%{proposal | language: "en"}, :system)

    {:noreply, socket} = Form.handle_event("save", %{"page" => %{"uri" => "reclaimed", "language" => "no"}}, socket)
    assert socket.assigns.pending_permalink_redirect.redirect.language == "en"
    assert Redirects.test_redirect(["no", "reclaimed"], "no") == {:error, {:redirects, :no_match}}
    assert Redirects.test_redirect(["no", "reclaimed"], "en") == {:ok, {:redirect, {"/elsewhere", 301}}}
    {:noreply, _socket} = Form.handle_event("skip_permalink_redirect", %{}, socket)
    assert Redirects.test_redirect(["en", "old-permalink"], "en") == {:error, {:redirects, :no_match}}
  end

  @tag capture_log: true
  test "failed saves leave destination redirects intact", %{socket: socket, page: page} do
    proposal = %{from: "/en/reclaimed", to: "/en/elsewhere", language: "en"}
    assert {:ok, _} = Redirects.create_permalink_redirect(proposal, :system)
    {:noreply, socket} = Form.handle_event("save", %{"page" => %{"uri" => "reclaimed", "title" => ""}}, socket)
    assert Brando.Repo.get!(Brando.Pages.Page, page.id).uri == "old-permalink"
    refute socket.assigns.pending_permalink_redirect
    assert Redirects.test_redirect(["en", "reclaimed"], "en") == {:ok, {:redirect, {"/en/elsewhere", 301}}}
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
