defmodule Brando.Meta.Model do
  @moduledoc """
  Meta functions for Brando models

  ## Usage:

      use Brando.Meta.Model, [
        singular: gettext("post"),
        plural: gettext("posts"),
        repr: fn (model) -> "interpolate from model" end,
        fields: [
          id: gettext("ID"),
          language: gettext("Language")]]

  ## Options:

    * `singular`: The singular form of the models representation
    * `plural`: The plural form of the models representation
    * `repr`: Function returning the repr of the record.
    * `fields`: Keyword list of fields in the model. Used for translation.
    * `hidden_fields`: Fields not shown in the detail view.

  """
  @doc false
  defmacro __using__(opts) do
    quote do
      def __fields__ do
        unquote(opts[:fields])
      end
      def __field__(field) do
        __fields__[field]
      end
      def __keys__ do
        Keyword.keys(__fields__())
      end
      def __hidden_fields__ do
        unquote(opts[:hidden_fields] || [])
      end
      def __name__(:singular), do: unquote(opts[:singular])
      def __name__(:plural), do: unquote(opts[:plural])
      def __repr__(model), do: unquote(opts[:repr]).(model)
    end
  end
end
