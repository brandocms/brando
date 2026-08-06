defmodule BrandoAdmin.Components.Form.AddonStatusesTest do
  # Phase 3 / E1 in the form audit.
  #
  # `assign_addon_statuses/1` runs from `finish_form_update/1`, which the generic
  # `update/2` clause reaches on EVERY parent re-render — Presence diffs
  # included. It recomputed data that is fixed for the life of the component
  # (schema traits, `Code.ensure_compiled!` on the live-preview module, the
  # transformer map) with plain `assign/2`.
  #
  # The transformer assigns were the sharp edge: they are STATE owned by
  # `reset_transformer_changesets/1`, and re-initialising them on every update
  # discarded whatever a transformer had already reported.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias BrandoAdmin.Components.Form

  setup do
    # `prepare_empty_entry/2` reads `current_user.config.content_language`; the
    # factory does not build a config.
    user = Factory.insert(:random_user)
    {:ok, user: %{user | config: %Brando.Users.UserConfig{content_language: "en"}}}
  end

  defp mounted_form(ctx) do
    {:ok, socket} = Form.mount(%Phoenix.LiveView.Socket{})

    {:ok, socket} =
      Form.update(
        %{
          id: "page_form",
          schema: Brando.Pages.Page,
          current_user: ctx.user,
          entry_id: nil,
          header: nil
        },
        socket
      )

    socket
  end

  defp re_render(socket, ctx) do
    # What a Presence diff looks like from this component's side: the parent
    # re-renders and hands the same props back.
    {:ok, socket} =
      Form.update(
        %{
          id: "page_form",
          schema: Brando.Pages.Page,
          current_user: ctx.user,
          presences: %{"someone" => %{}}
        },
        socket
      )

    socket
  end

  test "a re-render does not discard transformer changesets already collected", ctx do
    socket = mounted_form(ctx)

    # Mid-collection: one transformer has reported, one has not (see the
    # `:transformer_changeset` clause of update/2 — modelled directly here so the
    # test does not need a blueprint that declares transformers).
    #
    # `all_transformers_received?` must be `false` for this to assert anything.
    # `Page` declares no transformers, so `assign_transformer_statuses/1` would
    # compute `transformers == []` → `true`; asserting `true` would pass against
    # the pre-fix code that recomputed on every update.
    collected = %{cover: :some_changeset, hero: nil}

    socket = Phoenix.Component.assign(socket, :transformer_changesets, collected)
    socket = Phoenix.Component.assign(socket, :all_transformers_received?, false)

    socket = re_render(socket, ctx)

    assert socket.assigns.transformer_changesets == collected
    refute socket.assigns.all_transformers_received?
  end

  test "the static per-schema statuses survive a re-render unchanged", ctx do
    socket = mounted_form(ctx)

    # Asserted against the schema rather than against a snapshot of the socket:
    # comparing the socket to itself passes even if `assign_addon_statuses/1` is
    # deleted outright, since mount's seeds would simply persist.
    expected = %{
      has_blocks?: Brando.Pages.Page.has_trait(Brando.Trait.Blocks),
      has_meta?: Brando.Pages.Page.has_trait(Brando.Trait.Meta),
      has_revisioning?: Brando.Pages.Page.has_trait(Brando.Trait.Revisioned),
      has_scheduled_publishing?: Brando.Pages.Page.has_trait(Brando.Trait.ScheduledPublishing)
    }

    assert Map.take(socket.assigns, Map.keys(expected)) == expected

    socket = re_render(socket, ctx)

    assert Map.take(socket.assigns, Map.keys(expected)) == expected
  end

  test "has_meta? is still derived from the schema, not left at mount's false", ctx do
    # `mount/1` seeds `has_meta?: false` so the async-load render has it. That
    # seed is exactly why this one cannot become an `assign_new`.
    socket = mounted_form(ctx)

    assert socket.assigns.has_meta? == Brando.Pages.Page.has_trait(Brando.Trait.Meta)
    assert socket.assigns.has_meta? == true
  end

  test "has_alternates? still tracks the entry, not the first render", ctx do
    # The other plain assign: it reads `entry.id`, which is nil on a create form
    # and set once that form saves.
    socket = mounted_form(ctx)

    refute socket.assigns.has_alternates?

    entry = Factory.insert(:page, creator: ctx.user)
    socket = Phoenix.Component.assign(socket, :entry, entry)
    socket = re_render(socket, ctx)

    assert socket.assigns.has_alternates? == entry.id
  end
end
