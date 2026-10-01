defmodule BrandoAdmin.Components.Form.Block.NestedBlockFormTest do
  # `Render.nested_block_form/1` rebuilds what `<.inputs_for field={@form[:block]}>`
  # yields, persistent id included, so the root block can be change tracked.
  # It copies private LiveView logic: if an upgrade changes how `inputs_for`
  # names, ids or hides its forms, this fails instead of the editor drifting.
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias BrandoAdmin.Components.Form.Block.Render

  defp block_form(block) do
    %Brando.Pages.Page.Blocks{id: 7, entry_id: 1, sequence: 0, block: block}
    |> Ecto.Changeset.change()
    |> to_form(as: "entry_block", id: "entry_block_form-abc")
  end

  defp via_inputs_for(form) do
    assigns = %{form: form}

    ~H"""
    <.inputs_for :let={f} field={@form[:block]}>
      <i data-id={f.id} data-name={f.name} data-index={f.index} data-hidden={inspect(f.hidden)} />
    </.inputs_for>
    """
    |> rendered_to_string()
  end

  defp via_render(form) do
    f = Render.nested_block_form(form)
    assigns = %{f: f, hidden: Render.hidden_inputs(f)}

    ~H"""
    <input :for={{name, value} <- @hidden} type="hidden" name={name} value={value} />
    <i data-id={@f.id} data-name={@f.name} data-index={@f.index} data-hidden={inspect(@f.hidden)} />
    """
    |> rendered_to_string()
  end

  for {label, block} <- [
        persisted: %Brando.Content.Block{id: 3, uid: "abc", type: :module},
        new: %Brando.Content.Block{uid: "abc", type: :module}
      ] do
    test "matches inputs_for for a #{label} block" do
      form = block_form(unquote(Macro.escape(block)))
      squash = &(&1 |> String.replace(~r/>\s+</, "><") |> String.trim())
      assert squash.(via_render(form)) == squash.(via_inputs_for(form))
    end
  end
end
