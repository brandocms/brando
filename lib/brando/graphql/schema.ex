defmodule Brando.Schema do
  @moduledoc """
  Use this to import GQL queries and mutations
  """

  defmacro __using__(_) do
    quote do
      import Brando.Schema
    end
  end

  @doc """
  Imports all brando mutations
  """
  defmacro import_brando_mutations do
    quote do
      # brando mutations
      import_fields :image_mutations
      import_fields :page_mutations
      import_fields :page_fragment_mutations
      import_fields :user_mutations
    end
  end

  @doc """
  Imports all brando queries
  """
  defmacro import_brando_queries do
    quote do
      # brando queries
      import_fields :image_queries
      import_fields :page_queries
      import_fields :page_fragment_queries
      import_fields :user_queries
    end
  end
end
