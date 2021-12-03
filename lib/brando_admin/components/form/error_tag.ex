defmodule BrandoAdmin.Components.Form.ErrorTag do
  use BrandoAdmin, :component
  import Phoenix.HTML.Form, only: [input_id: 2]

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:feedback_for, fn -> nil end)
      |> assign_new(:translate_fn, fn ->
        {mod, fun} = assigns[:translator] || {Brando.web_module(ErrorHelpers), :translate_error}
        &apply(mod, fun, [&1])
      end)

    assigns =
      if assigns.relation do
        assign(assigns, :field, :"#{assigns.field}_id")
      else
        assigns
      end

    ~H"""
    <%= for error <- Keyword.get_values(@form.errors, @field) do %>
    <span
      id={"#{@form.id}-#{@field}-error"}
      class="field-error"
      phx-feedback-for={@feedback_for || input_id(@form, @field)}>
      <%= @translate_fn.(error) %>
    </span>
    <% end %>
    """
  end
end
