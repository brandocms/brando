defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.OverrideForm do
  @moduledoc """
  LiveComponent for gallery object override forms.

  Uses the unified override convention: nil = use default from media record.
  Shows reset icons when values differ from defaults. The `use_default_*` flags
  are not inputs: `GalleryObjectOverride.cast_override/2` derives each from its
  text. An image's caption is its `title`; a video's is its `caption`, and its
  `title` (plain) names the player. Captions are rich text.

  Text field resets use client-side JS (clearing the input and dispatching a
  change event). A video's playback settings are Default / On / Off
  (`PlaybackFlag`): Default stores nil and leaves the setting to the video.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.PlaybackFlag
  alias BrandoAdmin.Components.Form.Input.VideoQuality

  @caption_opts [extensions: ~w(p bold italic link)]

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:caption_opts, @caption_opts)}
  end

  def render(%{variant: :modal} = assigns) do
    ~H"""
    <div>
      <Input.input type={:hidden} field={@form[:object_id]} />
      <Input.input type={:hidden} field={@form[:object_type]} />
      <Input.input type={:hidden} field={@form[:placement]} />
      <Input.input type={:hidden} field={@form[:uid]} />

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
          <.playback_flags form={@form} />
          <VideoQuality.select
            field={@form[:quality]}
            choices={Map.get(@override_info, :quality_choices, [])}
            inherit={Map.get(@override_info, :quality_inherit, "")}
          />
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
      <Input.input type={:hidden} field={@form[:placement]} />
      <Input.input type={:hidden} field={@form[:uid]} />

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
        <.playback_flags form={@form} />
        <VideoQuality.select
          field={@form[:quality]}
          choices={Map.get(@override_info, :quality_choices, [])}
          inherit={Map.get(@override_info, :quality_inherit, "")}
        />
      <% end %>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  # The marker tells these choices from the on/off switches this form had
  # before (`GalleryObjectOverride.cast_override/2`).
  defp playback_flags(assigns) do
    ~H"""
    <div class="playback-flags">
      <input type="hidden" name={"#{@form.name}[playback_flags]"} value="true" />
      <PlaybackFlag.choice field={playback_field(@form, :autoplay)} label={gettext("Autoplay")} />
      <PlaybackFlag.choice field={playback_field(@form, :loop)} label={gettext("Loop")} />
      <PlaybackFlag.choice field={playback_field(@form, :muted)} label={gettext("Muted")} />
      <PlaybackFlag.choice field={playback_field(@form, :controls)} label={gettext("Controls")} />
      <PlaybackFlag.choice field={playback_field(@form, :preload)} label={gettext("Lazy load")} />
    </div>
    """
  end

  # A value whose `use_default_*` flag is on shows as Default, as the site
  # ignores it: the switches this form had before stored one for every
  # override without clearing the flag.
  defp playback_field(form, field) do
    if form[:"use_default_#{field}"].value in [false, "false"],
      do: form[field],
      else: %{form[field] | value: nil}
  end
end
