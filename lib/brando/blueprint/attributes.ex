defmodule Brando.Blueprint.Attributes do
  @moduledoc """
  ### Attributes

  #### Uniqueness

  To create an unique index in the db as well as running
  `unique_constraint` in the changeset:

      attribute :email, unique: true

  If you have fields that need to be unique together:

      attribute :email, unique: [with: :other_field]

  If you need uniqueness, but are fine with changing the attribute

      attribute :slug, unique: [prevent_collision: true]

  This is good for URL slugs. If it detects a collision it will add
  `-{x}` to the value, where x is the next in sequence.

  If you need uniqueness, but validated against another field - for
  instance if you have a `slug` field, but also a `language` field:

      attribute :slug, unique: [prevent_collision: :language]

  This allows you to have `%{slug: "test", language: "en"}` and
  `%{slug: "test", language: "dk"}` without erroring.

  For custom scopes, pass an arity-one callback that receives the changeset and
  returns the query used to check candidates. Declare every persisted database
  scope field with `:with` so the callback query, Ecto constraint, and generated
  unique index enforce the same contract:

      attribute :slug,
        unique: [
          prevent_collision: fn changeset ->
            language = Ecto.Changeset.get_field(changeset, :language)
            from entry in MyApp.Content.Entry, where: entry.language == ^language
          end,
          with: :language
        ]

  """

  alias Spark.Dsl.Extension

  def __attributes__(module) do
    module
    |> Extension.get_entities([:attributes])
    |> Enum.reverse()
  end

  def __attribute__(module, name) do
    Extension.get_persisted(module, {:attribute, name})
  end

  def __attribute_opts__(module, name) do
    module
    |> __attribute__(name)
    |> Map.get(:opts, [])
  end
end
