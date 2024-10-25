defmodule BrandoAdmin.Components.Form.Fieldset do
  use BrandoAdmin.Translator
  use BrandoAdmin, :component

  alias BrandoAdmin.Components.Form.Fieldset

  # prop current_user, :any
  # prop fieldset, :any
  # prop form, :any
  # prop translations, :any
  # prop parent_uploads, :any
  # prop form_cid, :any

  def render(assigns) do
    ~H"""
    <fieldset class={[
      @fieldset.size,
      @fieldset.align == :end && "align-end",
      @fieldset.style == :inline && "inline",
      @fieldset.shaded && "shaded"
    ]}>
      <Fieldset.Field.render
        :for={input <- @fieldset.fields}
        form={@form}
        translations={@translations}
        relations={@relations}
        input={input}
        parent_uploads={@parent_uploads}
        current_user={@current_user}
        form_cid={@form_cid}
      />
    </fieldset>
    """
  end
end
