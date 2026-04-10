defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.OverrideForm do
  @moduledoc """
  LiveComponent for gallery object override forms.

  Uses the unified override convention: nil = use default from media record.
  Shows reset icons when values differ from defaults.

  Text field resets use client-side JS (clearing the input and dispatching a
  change event). Toggle fields are standard toggles — users toggle them directly.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.Input

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(%{variant: :modal} = assigns) do
    ~H"""
    <div>
      <Input.input type={:hidden} field={@form[:object_id]} />
      <Input.input type={:hidden} field={@form[:object_type]} />

      <Input.override_text
        field={@form[:title]}
        label={gettext("Title")}
        default_value={@override_info.default_title}
      />

      <Input.override_text
        field={@form[:credits]}
        label={gettext("Credits")}
        default_value={@override_info.default_credits}
      />

      <%= if @override_info.object_type == :image do %>
        <Input.override_text
          field={@form[:alt]}
          label={gettext("Alt text")}
          default_value={@override_info.default_alt}
        />
      <% end %>

      <%= if @override_info.object_type == :video do %>
        <div class="video-config-section">
          <h4>{gettext("Video playback")}</h4>
          <Input.toggle tiny field={@form[:autoplay]} label={gettext("Autoplay")} />
          <Input.toggle tiny field={@form[:loop]} label={gettext("Loop")} />
          <Input.toggle tiny field={@form[:muted]} label={gettext("Muted")} />
          <Input.toggle tiny field={@form[:controls]} label={gettext("Controls")} />
          <Input.toggle tiny field={@form[:preload]} label={gettext("Preload")} />
        </div>
      <% end %>
    </div>
    """
  end

  def render(%{variant: :inline} = assigns) do
    ~H"""
    <div>
      <Input.input type={:hidden} field={@form[:object_id]} />
      <Input.input type={:hidden} field={@form[:object_type]} />

      <Input.override_text
        field={@form[:title]}
        label={gettext("Title")}
        default_value={@override_info.default_title}
      />

      <Input.override_text
        field={@form[:credits]}
        label={gettext("Credits")}
        default_value={@override_info.default_credits}
      />

      <%= if @override_info.object_type == :image do %>
        <Input.override_text
          field={@form[:alt]}
          label={gettext("Alt text")}
          default_value={@override_info.default_alt}
        />
      <% end %>

      <%= if @override_info.object_type == :video do %>
        <Input.toggle tiny field={@form[:autoplay]} label={gettext("Autoplay")} />
        <Input.toggle tiny field={@form[:loop]} label={gettext("Loop")} />
        <Input.toggle tiny field={@form[:muted]} label={gettext("Muted")} />
        <Input.toggle tiny field={@form[:controls]} label={gettext("Controls")} />
        <Input.toggle tiny field={@form[:preload]} label={gettext("Preload")} />
      <% end %>
    </div>
    """
  end
end
