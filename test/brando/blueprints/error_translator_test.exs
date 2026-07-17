defmodule Brando.Blueprint.ErrorTranslatorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Brando.Blueprint.ErrorTranslator
  alias Brando.Blueprint.Forms

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
    caller = self()

    log =
      capture_log(fn ->
        send(caller, {:translated, ErrorTranslator.translate_keys([:missing_field], form, Schema)})
      end)

    assert_receive {:translated, ["Missing field"]}
    assert log =~ "Could not get field `:missing_field` from form"
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
