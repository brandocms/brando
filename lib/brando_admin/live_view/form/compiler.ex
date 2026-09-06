defmodule BrandoAdmin.LiveView.Form.Compiler do
  @moduledoc """
  Internal compiler for the public `BrandoAdmin.LiveView.Form` API. It expands the
  shared LiveView setup without depending on the runtime hook implementation module.

  Form LiveViews keep using the public entry point:

      use BrandoAdmin.LiveView.Form, schema: MyApp.Projects.Project
  """

  defmacro __using__(opts), do: build(opts)

  @doc "Builds the setup expanded by the public form LiveView API."
  def build(opts) do
    schema = Keyword.fetch!(opts, :schema)
    skip_image_hooks = Keyword.get(opts, :skip_image_hooks, false)

    quote do
      use BrandoAdmin, :live_view

      def __authorization_resource__, do: {:form, unquote(schema)}

      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:setup, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_toast, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_progress_popup, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_alert, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_content_language, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_dirty_fields, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_active_field, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_block_presence, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_block_sync, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_modules, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_focal_point, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_focus, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_mutations, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_mutation_listener, unquote(schema)}})

      unless unquote(skip_image_hooks) do
        on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_images, unquote(schema)}})
      end

      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_asset_delivery, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_tiptap_link, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_videos, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_video_events, unquote(schema)}})

      # Catch port exits from image processing (ImageMagick, etc)
      on_mount({BrandoAdmin.LiveView.Form.Hooks, {:hooks_port_exits, unquote(schema)}})
    end
  end
end
