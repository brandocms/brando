defmodule Brando.Meta.GraphQL do
  @moduledoc """
  GraphQL META fields

  ## Usage

      use Brando.Meta.GraphQL

  """
  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

  @doc """
  Macro for adding META fields to migration
  """
  defmacro meta_fields do
    quote do
      Absinthe.Schema.Notation.field(:meta_title, :string)
      Absinthe.Schema.Notation.field(:meta_description, :string)
      Absinthe.Schema.Notation.field(:meta_image, :image_type)
    end
  end

  defmacro meta_params do
    quote do
      Absinthe.Schema.Notation.field(:meta_title, :string)
      Absinthe.Schema.Notation.field(:meta_description, :string)
      Absinthe.Schema.Notation.field(:meta_image, :upload_or_image)
    end
  end
end
