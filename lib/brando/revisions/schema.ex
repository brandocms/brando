defmodule Brando.Revisions.Schema do
  @moduledoc """
  Adds revisions support to schema

  ## Usage

      use Brando.Revisions.Schema

  Now, when using `Brando.Query`'s `mutation :create` and `mutation :update` macros,
  revisions will be created automatically for you.
  """

  defmacro __using__(_) do
    quote do
      def __revisioned__, do: true
    end
  end
end
