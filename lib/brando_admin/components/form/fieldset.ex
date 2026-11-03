defmodule BrandoAdmin.Components.Form.Fieldset do
  @moduledoc false
  use BrandoAdmin.Translator
  use BrandoAdmin, :component

  alias BrandoAdmin.Components.Form.Fieldset

  # prop current_user, :any
  # prop fieldset, :any
  # prop form, :any
  # prop translations, :any
  # prop form_cid, :any
  # prop read_generation, :integer — the form's `Boundary.read_generation/0`:
  #   a change draws the fields again, so inputs that keep read decisions
  #   (`Input.Entries`, in a subform's rows too) decide anew

  def render(assigns) do
    assigns = assign_new(assigns, :read_generation, fn -> nil end)

    ~H"""
    <fieldset
      :if={!@fieldset.superuser or superuser?(@current_user)}
      class={[
        @fieldset.size,
        @fieldset.label && "labelled",
        @fieldset.align == :end && "align-end",
        @fieldset.style == :inline && "inline",
        @fieldset.shaded && "shaded"
      ]}
    >
      <legend :if={@fieldset.label}>{g(@form.source.data.__struct__, @fieldset.label)}</legend>
      {if @fieldset.component, do: @fieldset.component.(assigns)}
      <Fieldset.Field.render
        :for={input <- @fieldset.fields}
        form={@form}
        relations={@relations}
        input={input}
        current_user={@current_user}
        form_cid={@form_cid}
        form_id={@form_id}
        read_generation={@read_generation}
      />
    </fieldset>
    """
  end

  defp superuser?(%{role: :superuser}), do: true
  defp superuser?(_), do: false
end
