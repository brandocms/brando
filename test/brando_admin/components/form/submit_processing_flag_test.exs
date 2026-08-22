defmodule BrandoAdmin.Components.Form.SubmitProcessingFlagTest do
  @moduledoc """
  `Primitives.submit_button/1` renders `disabled={@processing}`, so the flag is
  not decorative — while it is set the form cannot be submitted again, and the
  only way out is a page reload.

  `handle_event("save", …)` sets it on the way in and every exit is supposed to
  clear it. The transformer clause's did not: neither its `:self` success branch
  nor its changeset-error branch touched `:processing`, while the sibling
  blocks clause cleared it in both. `:listing` and `:new` navigate away, so the
  omission was invisible for the plain Save button and showed only on ⌘S
  ("Save and continue editing"), which stays on the form — the entry saved, and
  the button sat on "Processing. Please wait…" for good.

  The error branch is the worse half: a rejected save always stays on the form,
  so it always rendered a stuck spinner over its own validation errors. Seen in
  production on a Project failing its `one_of` listing_image/listing_video
  constraint, where it reads as "saving is broken" rather than "fix these
  fields".

  These drive `handle_event/3` directly. The flag is set by the *first* save
  round-trip (which only collects transformer data) and cleared by the second,
  so a mounted-LiveView test would have to model the collection handshake to
  observe what is a plain assign.
  """

  use ExUnit.Case, async: false
  use Brando.ConnCase

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias BrandoAdmin.Components.Form
  alias Phoenix.Component

  setup do
    user = Brando.Factory.insert(:random_user)
    {:ok, user: user, page: Brando.Factory.insert(:page, creator: user)}
  end

  defp save_socket(ctx, overrides) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:id, "page_form")
    |> Component.assign(:schema, Brando.Pages.Page)
    |> Component.assign(:singular, "page")
    |> Component.assign(:context, Brando.Pages)
    |> Component.assign(:entry, ctx.page)
    |> Component.assign(:entry_id, ctx.page.id)
    |> Component.assign(:current_user, ctx.user)
    |> Component.assign(:form_blueprint, Brando.Pages.Page.__form__(:default))
    |> Component.assign(:form, Phoenix.Component.to_form(Ecto.Changeset.change(ctx.page)))
    |> Component.assign(:has_blocks?, false)
    |> Component.assign(:has_transformers?, true)
    |> Component.assign(:all_transformers_received?, true)
    |> Component.assign(:transformer_changesets, %{})
    |> Component.assign(:processing, true)
    |> Component.assign(:save_redirect_target, :self)
    |> Component.assign(:live_preview_active?, false)
    |> Component.assign(:fields_demanding_live_preview_reassign, [])
    |> then(fn socket ->
      Enum.reduce(overrides, socket, fn {k, v}, acc -> Component.assign(acc, k, v) end)
    end)
  end

  test "a save that stays on the form clears the flag", ctx do
    # `:self` is what ⌘S ("Save and continue editing") sets, and the only
    # redirect target that renders the button again.
    socket = save_socket(ctx, [])

    {:noreply, socket} =
      Form.handle_event("save", %{"page" => %{"title" => "Still here"}}, socket)

    refute socket.assigns.processing,
           "the entry saved but the submit button stayed disabled — the form is locked until reload"
  end

  test "a rejected save clears the flag so the button is usable again", ctx do
    # A blank title fails the schema's own validation, so the save comes back
    # {:error, changeset} without needing a stubbed context. The changeset is
    # logged by the handler, which is not what this test is about.
    socket = save_socket(ctx, [])

    {{:noreply, socket}, _log} =
      with_log(fn -> Form.handle_event("save", %{"page" => %{"title" => ""}}, socket) end)

    refute socket.assigns.processing,
           "the submit button stays disabled over its own validation errors"
  end
end
