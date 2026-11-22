defmodule BrandoAdmin.RichTextDefaultFormTest do
  # The admin form checks rich text by the default form as well as by the
  # form it saves from: the note's default form draws its subtitle as rich
  # text, `:omitted` leaves the subtitle out and `:plain` draws it as plain
  # text. A value another editor ships into a named form reaches it as a
  # field change, with no cast, so only the form's check by the default form
  # stands between it and the save or the stored revision. A form that checks
  # its own rich text doesn't ship a value it refuses, but text written into a
  # form without the check (`put_written_form`, Translate with AI) ships as it
  # is, and so does whatever a node running older code sends: the tests ship
  # the value as field sync does, with no form of their own to type it.
  use Brando.LiveCase, async: true

  import Brando.EditSessionEditors, only: [await: 1]
  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias Brando.Revisions.Revision
  alias Brando.RichTextDefaultFormTest.Note

  @unsafe ~s{<p><a href="javascript:alert(1)">link</a></p>}

  setup do
    %{note: Repo.insert!(%Note{title: "Note", subtitle: "Stored"})}
  end

  defp open(conn, note, form) do
    path = if form, do: "/admin/rich-notes/update/#{note.id}/#{form}", else: "/admin/rich-notes/update/#{note.id}"
    {view, _html} = live_form(conn, path, "note_form")
    view
  end

  defp form_of(view), do: with_target(view, cid_of(view, "#note_form-el"))

  # A keystroke as the browser sends it: the whole form, one field changed
  defp type(view, field, value) do
    path = ["note", field]

    params =
      view
      |> render()
      |> form_params("#note_form_form")
      |> put_in(path, value)
      |> Map.put("_target", path)

    view |> element("#note_form_form") |> render_change(params)
  end

  # "Save and continue editing", with what the browser sends: the note has
  # no blocks, so one submit writes
  defp save(view, params) do
    view |> form_of() |> render_hook("save_redirect_target", %{})
    view |> element("#note_form_form") |> render_submit(params)
    render(view)
  end

  # Another editor's tab ships `html` as the subtitle, unchecked: the message
  # a form broadcasts on the entry's field-sync topic when an editor leaves a
  # field, from an editor who may change notes. It reaches `view`'s form as a
  # field change.
  defp other_ships_subtitle(view, note, html) do
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    tab = "other-editor-tab"
    change = %{field: :subtitle, value: html, assoc?: false, clock: {System.os_time(:millisecond), tab}}

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.entry("field_sync", Note, note.id),
      {:fields_shipped, %{changes: [change], clocks: nil, user_id: other.id, tab: tab, to: nil}}
    )

    await(fn -> Ecto.Changeset.get_field(form_source(view), :subtitle) == html end)
  end

  defp form_source(view) do
    {components, _, _} = :sys.get_state(view.pid).components

    Enum.find_value(components, fn
      {_cid, {BrandoAdmin.Components.Form, _id, assigns, _private, _prints}} -> assigns.form.source
      _ -> nil
    end)
  end

  defp revisions(note), do: Repo.aggregate(from(r in Revision, where: r.entry_id == ^note.id), :count)

  defp saved(note), do: Repo.get!(Note, note.id)

  describe "a top-level rich-text input of the default form" do
    # A typed value is cast, and the schema's changeset checks it by the
    # default form before the admin form does
    test "is refused on save from the default form", %{conn: conn, note: note} do
      view = open(conn, note, nil)
      type(view, "subtitle", @unsafe)
      save(view, view |> render() |> form_params("#note_form_form"))

      assert Keyword.has_key?(form_source(view).errors, :subtitle)
      assert saved(note).subtitle == "Stored"
    end

    # Another editor's change reaches the default form with no cast, so the
    # schema's changeset never sees it
    test "is refused on save from the default form when another editor's change put it there",
         %{conn: conn, note: note} do
      view = open(conn, note, nil)
      stale = view |> render() |> form_params("#note_form_form")

      other_ships_subtitle(view, note, @unsafe)
      save(view, stale)

      assert Keyword.has_key?(form_source(view).errors, :subtitle)
      assert saved(note).subtitle == "Stored"
    end

    for form <- ["omitted", "plain"] do
      test "is refused on save from the #{form} form when another editor's change put it there",
           %{conn: conn, note: note} do
        view = open(conn, note, unquote(form))
        # What the browser still sends: the form as it showed it
        stale = view |> render() |> form_params("#note_form_form")

        other_ships_subtitle(view, note, @unsafe)
        save(view, stale)

        assert Keyword.has_key?(form_source(view).errors, :subtitle)
        assert saved(note).subtitle == "Stored"
      end

      test "is refused in a revision stored from the #{form} form when another editor's change put it there",
           %{conn: conn, note: note} do
        view = open(conn, note, unquote(form))
        before = revisions(note)

        other_ships_subtitle(view, note, @unsafe)
        view |> form_of() |> render_hook("store_revision", %{})
        assert_push_event(view, "b:scroll_to_first_error", %{}, 5_000)

        assert Keyword.has_key?(form_source(view).errors, :subtitle)
        assert revisions(note) == before
      end
    end
  end

  describe "a refused field" do
    # The omitted form draws no subtitle, so no field can show the error: the
    # alert names it, under the default form's label, and a refusal the
    # editor is told about is no error in the log
    test "the form does not draw is named in the alert", %{conn: conn, note: note} do
      view = open(conn, note, "omitted")
      stale = view |> render() |> form_params("#note_form_form")
      other_ships_subtitle(view, note, @unsafe)

      log = capture_log(fn -> save(view, stale) end)

      assert_push_event(view, "b:alert", %{type: "error", html: html})
      assert html =~ "Lede"
      refute log =~ "Could not get field"
      refute log =~ "Changeset errors"
    end

    # The refused revision put its changeset in the form; the corrected one
    # arrives as a field change, with no cast to clear the old error
    test "shows no error once a corrected revision is stored", %{conn: conn, note: note} do
      view = open(conn, note, "plain")

      other_ships_subtitle(view, note, @unsafe)
      view |> form_of() |> render_hook("store_revision", %{})
      assert_push_event(view, "b:scroll_to_first_error", %{}, 5_000)
      assert Keyword.has_key?(form_source(view).errors, :subtitle)

      before = revisions(note)
      other_ships_subtitle(view, note, "<p>Safe</p>")
      view |> form_of() |> render_hook("store_revision", %{})
      await(fn -> revisions(note) == before + 1 end)

      refute Keyword.has_key?(form_source(view).errors, :subtitle)
      refute view |> render() |> Floki.parse_document!() |> Floki.find(".field-error") |> Enum.any?()
    end
  end
end
