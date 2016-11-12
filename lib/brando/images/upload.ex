defmodule Brando.Images.Upload do
  @moduledoc """
  Handles uploads for Brando.Image, and Brando.Portfolio.Image.
  Processing function for image uploads.
  """
  import Brando.Images.Utils, only: [create_image_sizes: 1]
  import Brando.Upload

  defmacro __using__(_) do
    quote do
      require Logger
      import unquote(__MODULE__)

      @doc """
      Checks `params` for Plug.Upload fields and passes them on.
      Fields in the `put_fields` map are added to the schema.
      Returns {:ok, schema} or raises
      """
      def check_for_uploads(params, current_user, cfg, put_fields \\ nil) do
        Enum.reduce(filter_plugs(params), [], fn (named_plug, _) ->
          handle_upload(named_plug,
                        &create_image_struct/1,
                        current_user,
                        put_fields,
                        __MODULE__,
                        cfg)
        end)
      end
    end
  end

  @doc """
  Handles Plug.Upload for our modules.
  This is the handler for Brando.Image and Brando.Portfolio.Image
  """
  def handle_upload({name, plug}, process_fn, user, put_fields, schema, cfg) do
    with {:ok, upload} <- process_upload(plug, cfg),
         {:ok, processed_field} <- process_fn.(upload)
    do
      params = Map.put(put_fields, name, processed_field)
      apply(schema, :create, [params, user])
    else
      err -> handle_upload_error(err)
    end
  end

  @doc """
  Passes upload to create_image_sizes.
  """
  def create_image_struct(upload) do
    create_image_sizes(upload)
  end
end
