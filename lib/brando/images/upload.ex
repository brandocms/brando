defmodule Brando.Images.Upload do
  @moduledoc """
  Same principle as ImageField, only this one has its own table.
  We get the config from `image.series.category.cfg`
  """

  import Brando.Images.Utils

  defmacro __using__(_) do
    quote do
      import Brando.Images.Utils
      import unquote(__MODULE__)
      @doc """
      Checks `params` for Plug.Upload fields and passes them on.
      Fields in the `put_fields` map are added to the model.
      Returns {:ok, model} or raises
      """
      def check_for_uploads(params, current_user, cfg, put_fields \\ nil) do
        params = params
        |> filter_plugs
        |> Enum.reduce([], fn (plug, acc) -> handle_upload(plug, acc, current_user, put_fields, __MODULE__, cfg) end)
      end
    end
  end

  def handle_upload({name, plug}, _acc, current_user, put_fields, module, cfg) do
    {:ok, file} = do_upload(plug, cfg)
    params = Map.put(put_fields, name, file)
    apply(module, :create, [params, current_user])
  end

end