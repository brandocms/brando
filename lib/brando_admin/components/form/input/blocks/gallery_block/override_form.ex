defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.OverrideForm do
  @moduledoc """
  LiveComponent for gallery object override forms.

  Uses the unified override convention: nil = use default from media record.
  Shows reset icons when values differ from defaults. The `use_default_*` flags
  are not inputs: `GalleryObjectOverride.cast_override/2` derives each from its
  text. An image's caption is its `title`; a video's is its `caption`, and its
  `title` (plain) names the player. Captions are rich text.

  Text field resets use client-side JS (clearing the input and dispatching a
  change event). Toggle fields are standard toggles — users toggle them directly.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.Input

  @caption_opts [extensions: ~w(p bold italic link)]

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:caption_opts, @caption_opts)}
  end

  def render(%{variant: :modal} = assigns) do
    ~H"""
    <div>
      <Input.input type={:hidden} field={@form[:object_id]} />
      <Input.input type={:hidden} field={@form[:object_type]} />

      <%= if @override_info.object_type == :image do %>
        <Input.rich_text
          field={@form[:title]}
          label={gettext("Caption")}
          default_value={Brando.Captions.library_html(@override_info.default_title)}
          reset
          opts={@caption_opts}
        />
      <% else %>
        <Input.override_text
          field={@form[:title]}
          label={gettext("Title")}
          default_value={@override_info.default_title}
        />
        <Input.rich_text
          field={@form[:caption]}
          label={gettext("Caption")}
          default_value={Brando.Captions.library_html(@override_info.default_title)}
          reset
          opts={@caption_opts}
        />
      <% end %>

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

      <%= if @override_info.object_type == :image do %>
        <Input.rich_text
          field={@form[:title]}
          label={gettext("Caption")}
          default_value={Brando.Captions.library_html(@override_info.default_title)}
          reset
          opts={@caption_opts}
        />
      <% else %>
        <Input.override_text
          field={@form[:title]}
          label={gettext("Title")}
          default_value={@override_info.default_title}
        />
        <Input.rich_text
          field={@form[:caption]}
          label={gettext("Caption")}
          default_value={Brando.Captions.library_html(@override_info.default_title)}
          reset
          opts={@caption_opts}
        />
      <% end %>

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
