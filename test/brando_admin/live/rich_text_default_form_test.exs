defmodule BrandoAdmin.RichTextDefaultFormTest do
  # The admin form checks rich text by the default form as well as by the
  # form it saves from: the note's default form draws its subtitle as rich
  # text, `:omitted` leaves the subtitle out and `:plain` draws it as plain
  # text. A value another editor ships into a named form reaches it as a
  # field change, with no cast, so only the form's check by the default form
  # stands between it and the save or the stored revision.
  use Brando.LiveCase, async: true

  import Brando.EditSessionEditors, only: [await: 1]
  import Ecto.Query, only: [from: 2]

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

  defp other_editor(note, form \\ nil) do
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    open(log_in_user(Phoenix.ConnTest.build_conn(), other), note, form)
  end

  # Another editor types `html` into the subtitle and leaves the field: the
  # value reaches `view`'s form as a field change
  defp other_types_subtitle(other_view, view, html) do
    type(other_view, "subtitle", html)
    other_view |> form_of() |> render_hook("focus", %{"field" => "note[subtitle]"})
    other_view |> form_of() |> render_hook("blur", %{"field" => "note[subtitle]"})
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

    # Another editor's change on the plain form reaches the default form
    # with no cast, so the schema's changeset never sees it
    test "is refused on save from the default form when another editor's change put it there",
         %{conn: conn, note: note} do
      view = open(conn, note, nil)
      other_view = other_editor(note, "plain")
      stale = view |> render() |> form_params("#note_form_form")

      other_types_subtitle(other_view, view, @unsafe)
      save(view, stale)

      assert Keyword.has_key?(form_source(view).errors, :subtitle)
      assert saved(note).subtitle == "Stored"
    end

    for form <- ["omitted", "plain"] do
      test "is refused on save from the #{form} form when another editor's change put it there",
           %{conn: conn, note: note} do
        view = open(conn, note, unquote(form))
        other_view = other_editor(note)
        # What the browser still sends: the form as it showed it
        stale = view |> render() |> form_params("#note_form_form")

        other_types_subtitle(other_view, view, @unsafe)
        save(view, stale)

        assert Keyword.has_key?(form_source(view).errors, :subtitle)
        assert saved(note).subtitle == "Stored"
      end

      test "is refused in a revision stored from the #{form} form when another editor's change put it there",
           %{conn: conn, note: note} do
        view = open(conn, note, unquote(form))
        other_view = other_editor(note)
        before = revisions(note)

        other_types_subtitle(other_view, view, @unsafe)
        view |> form_of() |> render_hook("store_revision", %{})
        assert_push_event(view, "b:scroll_to_first_error", %{}, 5_000)

        assert Keyword.has_key?(form_source(view).errors, :subtitle)
        assert revisions(note) == before
      end
    end
  end
end
