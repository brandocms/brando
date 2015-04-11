defmodule Brando.Meta do
  @moduledoc """
  Meta functions for Brando models

  ## Usage:

      use Brando.Meta,
        [singular: "post",
         plural: "poster",
         repr: fn (model) -> "interpolate from model" end,
         fields: [
            id: "ID",
            language: "Språk"]]

  ## Options:

    * `singular`: The singular form of the models representation
    * `plural`: The plural form of the models representation
    * `repr`: Function returning the repr of the record.
    * `fields`: Keyword list of fields in the model. Used for translation.

  """
  @doc false
  defmacro __using__(opts) do
    quote do
      def __name__(:singular), do: unquote(opts[:singular])
      def __name__(:plural), do: unquote(opts[:plural])
      def __repr__(model), do: unquote(opts[:repr]).(model)
      def __fields__ do
        Keyword.keys(unquote(opts[:fields]))
      end
      def __hidden_fields__ do
        unquote(opts[:hidden_fields] || [])
      end
      use Linguist.Vocabulary
      locale "no", [model: unquote(opts[:fields])]
    end
  end
end