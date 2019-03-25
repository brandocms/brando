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
  defmacro __using__(_) do
    raise "META/schemas are deprecated. Remove."
  end
end
