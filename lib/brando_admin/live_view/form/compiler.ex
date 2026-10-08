defmodule BrandoAdmin.LiveView.Form.Compiler do
  @moduledoc """
  Internal compiler for the public `BrandoAdmin.LiveView.Form` API. It expands the
  shared LiveView setup without depending on the runtime hook implementation module.

  Form LiveViews keep using the public entry point:

      use BrandoAdmin.LiveView.Form, schema: MyApp.Projects.Project
  """

  @hooks [
    :setup,
    :hooks_toast,
    :hooks_progress_popup,
    :hooks_alert,
    :hooks_content_language,
    :hooks_dirty_fields,
    :hooks_active_field,
    :hooks_block_presence,
    :hooks_block_sync,
    :hooks_modules,
    :hooks_focal_point,
    :hooks_focus,
    :hooks_mutations,
    :hooks_mutation_listener,
    :hooks_images,
    :hooks_asset_delivery,
    :hooks_processing_watch,
    :hooks_tiptap_link,
    :hooks_notes,
    :hooks_videos,
    :hooks_video_events,
    # Catch port exits from image processing (ImageMagick, etc)
    :hooks_port_exits
  ]

  @doc """
  The `BrandoAdmin.LiveView.Form.Hooks` a form LiveView runs on mount, in
  order. A view that picks its schema at runtime (the frontend editor) runs
  the same list itself.
  """
  def hooks(opts \\ []) do
    if Keyword.get(opts, :skip_image_hooks, false), do: List.delete(@hooks, :hooks_images), else: @hooks
  end

  defmacro __using__(opts), do: build(opts)

  @doc "Builds the setup expanded by the public form LiveView API."
  def build(opts) do
    schema = Keyword.fetch!(opts, :schema)

    mounts =
      for hook <- hooks(opts) do
        quote do: on_mount({BrandoAdmin.LiveView.Form.Hooks, {unquote(hook), unquote(schema)}})
      end

    quote do
      use BrandoAdmin, :live_view

      def __authorization_resource__, do: {:form, unquote(schema)}

      unquote_splicing(mounts)
    end
  end
end
