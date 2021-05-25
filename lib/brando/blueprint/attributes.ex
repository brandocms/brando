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

  """

  alias Brando.Blueprint.Attribute
  alias Brando.Blueprint.Relation

  @valid_attributes [
    {:array, :map},
    :array,
    :boolean,
    :date,
    :datetime,
    :enum,
    :naive_datetime,
    :decimal,
    :file,
    :float,
    :gallery,
    :image,
    :integer,
    :language,
    :map,
    :slug,
    :status,
    :string,
    :text,
    :time,
    :timestamp,
    :uuid,
    :video,
    :villain
  ]
  def validate_attr!(type) when type in @valid_attributes, do: true
  def validate_attr!({:__aliases__, _, _}), do: true

  def validate_attr!(type),
    do: raise("Unknown type `#{inspect(type)}` given in blueprint")

  def build_attr(name, type, opts \\ [])

  def build_attr(name, :language, opts) do
    default_languages =
      case Keyword.get(opts, :languages) do
        nil ->
          Brando.config(:languages) ||
            [
              [value: "en", text: "English"],
              [value: "no", text: "Norsk"]
            ]

        supplied_langs ->
          supplied_langs
      end

    languages =
      Enum.map(default_languages, fn [value: lang_code, text: _] ->
        String.to_atom(lang_code)
      end)

    %Attribute{
      name: name,
      type: :language,
      opts: %{values: languages, required: true}
    }
  end

  def build_attr(name, :file, opts) do
    %Attribute{
      name: name,
      type: :file,
      opts: opts |> Enum.into(%{}) |> Brando.Utils.map_to_struct(Brando.Type.FileConfig)
    }
  end

  def build_attr(name, :image, :db) do
    %Attribute{
      name: name,
      type: :image,
      opts: %{db: true, required: true}
    }
  end

  def build_attr(name, :image, opts) do
    %Relation{
      name: name,
      type: :image,
      opts: opts |> Enum.into(%{}) |> Brando.Utils.map_to_struct(Brando.Type.ImageConfig)
    }
  end

  def build_attr(name, type, opts) do
    %Attribute{
      name: name,
      type: type,
      opts: Enum.into(opts, %{})
    }
  end

  defmacro attributes(do: block) do
    attributes(__CALLER__, block)
  end

  defp attributes(_caller, block) do
    quote generated: true, location: :keep do
      Module.register_attribute(__MODULE__, :attrs, accumulate: true)
      unquote(block)
    end
  end

  defmacro attribute(name, type, opts \\ []) do
    validate_attr!(type)
    attribute(__CALLER__, name, type, opts)
  end

  defp attribute(_caller, name, type, opts) do
    quote location: :keep do
      attr =
        build_attr(
          unquote(name),
          unquote(type),
          unquote(opts)
        )

      Module.put_attribute(__MODULE__, :attrs, attr)
    end
  end
end
