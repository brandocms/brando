defmodule BrandoAdmin.Components.Form.ErrorTag do
  use BrandoAdmin, :component
  import Phoenix.HTML.Form, only: [input_id: 2]

  def render(assigns) do
    assigns =
      assign_new(assigns, :translate_fn, fn ->
        {mod, fun} = assigns[:translator] || {Brando.web_module(ErrorHelpers), :translate_error}
        &apply(mod, fun, [&1])
      end)

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
