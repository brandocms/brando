defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.OverrideForm do
  @moduledoc """
  LiveComponent wrapper for gallery object override forms.

  Normalizes checkbox values in update/2 to handle the case where
  form[:field].value returns raw string params ("false") instead of
  properly cast booleans.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.Input

  @doc """
  Renders the override form fields.

  ## Assigns

    * `:form` - The override form from inputs_for
    * `:override_info` - Map with :default_title, :default_credits, :default_alt, :object_type
    * `:variant` - Either `:modal` (checkbox before input) or `:inline` (toggle after input)

  """
  def update(assigns, socket) do
    use_default_title = normalize_checkbox(assigns.form[:use_default_title].value)
    use_default_credits = normalize_checkbox(assigns.form[:use_default_credits].value)
    use_default_alt = normalize_checkbox(assigns.form[:use_default_alt].value)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:use_default_title, use_default_title)
     |> assign(:use_default_credits, use_default_credits)
     |> assign(:use_default_alt, use_default_alt)}
  end

  defp normalize_checkbox(value) do
    Phoenix.HTML.Form.normalize_value("checkbox", value)
  end

  def render(%{variant: :modal} = assigns) do
    ~H"""
    <div>
      <Input.input type={:hidden} field={@form[:object_id]} />
      <Input.input type={:hidden} field={@form[:object_type]} />

      <Input.input
        type={:checkbox}
        field={@form[:use_default_title]}
        label={gettext("Use default title")}
      />

      <Input.input
        type={:text}
        field={@form[:title]}
        label={gettext("Title")}
        disabled={@use_default_title}
        placeholder={if @use_default_title, do: gettext("Default: %{title}", title: @override_info.default_title)}
      />

      <Input.input
        type={:checkbox}
        field={@form[:use_default_credits]}
        label={gettext("Use default credits")}
      />

      <Input.input
        type={:text}
        field={@form[:credits]}
        label={gettext("Credits")}
        disabled={@use_default_credits}
        placeholder={if @use_default_credits, do: gettext("Default: %{credits}", credits: @override_info.default_credits)}
      />

      <%= if @override_info.object_type == :image do %>
        <Input.input
          type={:checkbox}
          field={@form[:use_default_alt]}
          label={gettext("Use default alt text")}
        />

        <Input.input
          type={:text}
          field={@form[:alt]}
          label={gettext("Alt text")}
          disabled={@use_default_alt}
          placeholder={if @use_default_alt, do: gettext("Default: %{alt}", alt: @override_info.default_alt)}
        />
      <% end %>
    </div>
    """
  end

  def render(%{variant: :inline} = assigns) do
    ~H"""
    <div>
      <Input.input type={:hidden} field={@form[:object_id]} />
      <Input.input type={:hidden} field={@form[:object_type]} />

      <Input.text
        field={@form[:title]}
        label={gettext("Title")}
        disabled={@use_default_title}
        placeholder={if @use_default_title, do: gettext("Default: %{title}", title: @override_info.default_title)}
      />

      <Input.toggle tiny field={@form[:use_default_title]} label={gettext("Use default title")} />

      <Input.text
        field={@form[:credits]}
        label={gettext("Credits")}
        disabled={@use_default_credits}
        placeholder={if @use_default_credits, do: gettext("Default: %{credits}", credits: @override_info.default_credits)}
      />

      <Input.toggle tiny field={@form[:use_default_credits]} label={gettext("Use default credits")} />

      <%= if @override_info.object_type == :image do %>
        <Input.text
          field={@form[:alt]}
          label={gettext("Alt text")}
          disabled={@use_default_alt}
          placeholder={if @use_default_alt, do: gettext("Default: %{alt}", alt: @override_info.default_alt)}
        />

        <Input.toggle tiny field={@form[:use_default_alt]} label={gettext("Use default alt text")} />
      <% end %>
    </div>
    """
  end
end
