defmodule Brando.Gallery.Schema do
  @moduledoc """
  Schema macro for Gallery
  """
  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :gallery_fields, accumulate: true)

      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    gallery_fields = Module.get_attribute(env.module, :gallery_fields)
    compile(gallery_fields)
  end

  @doc false
  def compile(gallery_fields) do
    quote do
      def __gallery_fields__ do
        unquote(Macro.escape(gallery_fields))
      end
    end
  end

  @doc """
  Macro for villain schema fields.
  """
  defmacro gallery(field \\ :image_series) do
    quote do
      Module.put_attribute(
        __MODULE__,
        :gallery_fields,
        unquote(field)
      )

      belongs_to unquote(field), Brando.ImageSeries
    end
  end
end
