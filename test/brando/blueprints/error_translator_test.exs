defmodule Brando.Blueprint.ErrorTranslatorTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.ErrorTranslator
  alias Brando.Blueprint.Forms
  alias Brando.Test.OwnLog
  alias Ecto.Changeset

  defmodule Schema do
    @moduledoc false

    def __modules__, do: %{gettext: Brando.Gettext}
    def __naming__, do: %{domain: "ErrorTest", schema: "Entry"}
  end

  test "uses configured labels and humanizes hidden or missing labels" do
    form =
      form_with_fields([
        %Forms.Input{name: :title, type: :text, opts: [label: "Project title"]},
        %Forms.Input{name: :status, type: :status, opts: [label: :hidden]},
        %Forms.Input{name: :cover_video, type: :video, opts: []},
        %Forms.Input{name: :summary, type: :text, opts: [label: "  "]},
        %Forms.Subform{name: :related_items, label: nil}
      ])

    assert ErrorTranslator.translate_keys(
             [:title, :status, :cover_video_id, :summary, :related_items],
             form,
             Schema
           ) == ["Project title", "Status", "Cover video", "Summary", "Related items"]
  end

  test "unknown error keys remain readable and are logged" do
    form = form_with_fields([])

    log =
      OwnLog.capture(fn ->
        assert ErrorTranslator.translate_keys([:missing_field], form, Schema) == ["Missing field"]
      end)

    assert log =~ "Could not get field :missing_field from form"

    # `inspect/2` of the whole `Forms.Form` would be over a hundred lines per
    # occurrence, and four occurrences in this suite alone. What a developer
    # needs is the key that was missing and the keys that were available, so
    # pin that the fields list is there and the struct dump is not.
    assert log =~ "Fields in this form: []"
    refute log =~ "%Brando.Blueprint.Forms.Form{"
  end

  test "meta drawer fields use the drawer's translated labels without logging" do
    form = form_with_fields([])

    log =
      OwnLog.capture(fn ->
        Gettext.with_locale(Brando.Gettext, "no", fn ->
          assert ErrorTranslator.translate_keys([:meta_canonical_url, :meta_title], form, Schema) ==
                   [
                     Gettext.dgettext(Brando.Gettext, "default", "Canonical URL"),
                     Gettext.dgettext(Brando.Gettext, "default", "Meta title")
                   ]

          refute ErrorTranslator.translate_keys([:meta_canonical_url], form, Schema) == ["Meta canonical url"]
        end)
      end)

    refute log =~ "Could not get field"
  end

  describe "describe/3" do
    # Each invalid var of a page under its own number, and the nested field
    # under the var's label, in the editor's language
    test "names a nested field under its schema's label, one entry per item" do
      changeset = page_with_invalid_vars(2)
      page_form = Brando.Pages.Page.__form__()

      Gettext.with_locale(Brando.Gettext, "no", fn ->
        variables = Gettext.dgettext(Brando.Gettext, "pages_page", "Page variables")
        label = Brando.Content.Transfer.Labels.field(Brando.Content.Var, :label)
        refute label == "Label"

        assert ErrorTranslator.describe(changeset, page_form, &message/1) == [
                 {"#{variables} 1 → #{label}", "can't be blank"},
                 {"#{variables} 2 → #{label}", "can't be blank"}
               ]
      end)
    end

    test "a single item is not numbered" do
      assert [{"Page variables → Label", "can't be blank"}] =
               ErrorTranslator.describe(page_with_invalid_vars(1), Brando.Pages.Page.__form__(), &message/1)
    end

    # A changeset from inside a restore that isn't the entry's (its job, its
    # identifier) with an error under a name the form also has
    test "a changeset that is not a Blueprint's goes by humanized names" do
      changeset = %Oban.Job{} |> Changeset.change() |> Changeset.add_error(:title, "is invalid")

      assert ErrorTranslator.describe(changeset, Brando.Pages.Page.__form__(), &message/1) == [
               {"Title", "is invalid"}
             ]

      identifier =
        %Brando.Content.Identifier{} |> Changeset.change() |> Changeset.add_error(:title, "is invalid")

      assert ErrorTranslator.describe(identifier, Brando.Pages.Page.__form__(), &message/1) == [
               {"Title", "is invalid"}
             ]
    end
  end

  defp message({message, _opts}), do: message

  defp page_with_invalid_vars(count) do
    vars =
      for n <- 1..count do
        %Brando.Content.Var{key: "key-#{n}"}
        |> Changeset.change()
        |> Changeset.add_error(:label, "can't be blank", validation: :required)
      end

    %Brando.Pages.Page{vars: []} |> Changeset.change() |> Changeset.put_assoc(:vars, vars)
  end

  defp form_with_fields(fields) do
    %Forms.Form{
      tabs: [
        %Forms.Tab{
          name: "Content",
          fields: [%Forms.Fieldset{fields: fields}]
        }
      ]
    }
  end
end
