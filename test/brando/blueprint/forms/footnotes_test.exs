defmodule Brando.Blueprint.Forms.FootnotesTest do
  use ExUnit.Case, async: true
  alias Brando.Blueprint.Forms
  alias Brando.Blueprint.Forms.Footnotes

  defp form(inputs), do: %Forms.Form{tabs: [%Forms.Tab{fields: [%Forms.Fieldset{fields: inputs}]}], blocks: []}

  test "rich text does not enable footnotes implicitly" do
    assert Footnotes.config([]) == nil
    assert Footnotes.config(extensions: ["all"]) == nil
    assert Footnotes.config(footnotes: false) == nil
    assert_raise ArgumentError, ~r/declare/, fn -> Footnotes.config(footnotes: true) end
  end

  test "an opted-in input mounts its dedicated owner and preserves a disabled configuration" do
    input = %Forms.Input{name: :body, type: :rich_text, opts: [footnotes: [blocks: :body_notes, module_set: "Sources"]]}
    mounted = Footnotes.mount_fields(form([input]))
    assert [%{name: :body_notes, opts: opts}] = mounted.blocks
    assert opts[:footnote_fields][:body] == %{blocks: :body_notes, module_set: "Sources", enabled: true}
    assert Footnotes.config(footnotes: [enabled: false, blocks: :body_notes, module_set: "Sources"]).enabled == false
  end

  test "rejects sharing a footnote owner with a regular block field" do
    input = %Forms.Input{name: :body, type: :rich_text, opts: [footnotes: [blocks: :blocks, module_set: "Sources"]]}
    form = %{form([input]) | blocks: [%Forms.Input{name: :blocks, type: :blocks}]}
    assert_raise ArgumentError, ~r/regular blocks editor/, fn -> Footnotes.mount_fields(form) end
  end
end
