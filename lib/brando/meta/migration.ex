defmodule Brando.Meta.Migration do
  @moduledoc """
  Migration META fields

  ## Usage

      use Brando.Villain.Migration

  Add fields to your schema:

      table "bla" do
        meta_fields()
      end

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
      Ecto.Migration.add(:meta_title, :text)
      Ecto.Migration.add(:meta_description, :text)
      Ecto.Migration.add(:meta_image, :map)
    end
  end
end
