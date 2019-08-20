defmodule Brando.Meta.Schema do
  @moduledoc """
  Macro for mapping META fields to schema

  ## Example

  In your schema:

      meta_schema do
        field :description, [:meta_description], &Brando.HTML.truncate(&1, 155)
        field :title, [:heading], &Brando.HTML.truncate(&1, 60)
        field :image, [:cover]
      end

  """

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.Meta.Schema, only: [meta_schema: 1]
      Module.register_attribute(__MODULE__, :meta_fields, accumulate: true)
    end
  end

  defmacro meta_schema([do: block]), do:
    do_meta_schema(block)

  defp do_meta_schema(block) do
    prelude =
      quote do
        try do
          import Brando.Meta.Schema
          unquote(block)
        after
          :ok
        end
      end

    postlude =
      quote unquote: false do
        fields = @meta_fields |> Enum.reverse()

        def __meta_schema__(:fields), do: unquote(fields)

        def extract_meta(data) do
        Brando.META.Schema.extract_meta(__MODULE__, data)
        end
      end

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end

  @doc """
  Defines a META field and how to extract data against our schema
  """
  defmacro field(name, path, mutator_function) do
    Module.put_attribute(__MODULE__, :meta_fields, name)

    quote do
      def __meta_field__(name, data) do
        value = get_in(data, Enum.map(unquote(path), &Access.get/1))
        unquote(mutator_function).(value)
      end
    end
  end

  @doc """
  Extract META information from `data` against `mod`'s `meta_schema`
  """
  def extract_meta(mod, data) do
    Enum.reduce(
      mod.__meta_schema__(:fields),
      %{},
      fn name, acc ->
        Map.put(acc, name, mod.__meta_field__(name, data))
      end
    )
  end
end
