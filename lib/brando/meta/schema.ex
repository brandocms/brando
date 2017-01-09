defmodule Brando.Meta.Schema do
  @moduledoc """
  Meta functions for Brando schemas

  ## Usage:

      use Brando.Meta.Schema, [
        singular: gettext("post"),
        plural: gettext("posts"),
        repr: fn (schema) -> "interpolate from schema" end,
        fields: [
          id: gettext("ID"),
          language: gettext("Language")
        ],
        fieldsets: [
          post_info: gettext("Post information")
        ],
        help: [
          language: gettext("This sets the wanted language for the post")
        ]
      ]

  ## Options:

    * `singular`: The singular form of the schema's representation
    * `plural`: The plural form of the schema's representation
    * `repr`: Function returning the repr of the record.
    * `fields`: Keyword list of fields in the schema. Used for translation.
    * `fieldsets`: Keyword list of fieldsets. Used in forms for gettext translation.
    * `help:`: Keyword list of help text for the fields in the schema.
    * `hidden_fields`: Fields not shown in the detail view.

  """
  @doc false
  defmacro __using__(opts) do
    quote do
      def __fields__ do
        unquote(opts[:fields])
      end
      def __field__(field) do
        __fields__()[field]
      end
      def __fieldsets__ do
        unquote(opts[:fieldsets] || [])
      end
      def __fieldset__(fieldset) do
        __fieldsets__()[fieldset]
      end
      def __help__ do
        unquote(opts[:help] || [])
      end
      def __help_for__(field) do
        __help__()[field]
      end
      def __keys__ do
        Keyword.keys(__fields__())
      end
      def __hidden_fields__ do
        unquote(opts[:hidden_fields] || [])
      end
      def __name__(:singular), do: unquote(opts[:singular])
      def __name__(:plural), do: unquote(opts[:plural])
      def __repr__(schema), do: unquote(opts[:repr]).(schema)
    end
  end
end
