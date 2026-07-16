defmodule BrandoAdmin.LiveView.Form.Compiler do
  @moduledoc """
  Compiles the shared admin form LiveView setup without depending on the runtime
  hook implementation module.

  Use this module when defining form LiveViews:

      use BrandoAdmin.LiveView.Form.Compiler, schema: MyApp.Projects.Project
  """

  defmacro __using__(opts), do: build(opts)

  @doc false
  def build(opts) do
    schema = Keyword.fetch!(opts, :schema)
    skip_image_hooks = Keyword.get(opts, :skip_image_hooks, false)

    quote do
      use BrandoAdmin, :live_view

      on_mount({BrandoAdmin.LiveView.Form, {:setup, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_progress_popup, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_alert, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_content_language, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_dirty_fields, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_active_field, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_block_presence, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_block_sync, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_modules, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_focal_point, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_focus, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_mutations, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_mutation_listener, unquote(schema)}})

      unless unquote(skip_image_hooks) do
        on_mount({BrandoAdmin.LiveView.Form, {:hooks_images, unquote(schema)}})
      end

      on_mount({BrandoAdmin.LiveView.Form, {:hooks_asset_delivery, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_tiptap_link, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_videos, unquote(schema)}})
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_video_events, unquote(schema)}})

      # Catch port exits from image processing (ImageMagick, etc)
      on_mount({BrandoAdmin.LiveView.Form, {:hooks_port_exits, unquote(schema)}})
    end
  end
end
