defmodule Brando.Blueprint.DataLayer do
  @valid_attributes [
    :array,
    :boolean,
    :date,
    :datetime,
    :decimal,
    :file,
    :float,
    :gallery,
    :image,
    :integer,
    :map,
    :slug,
    :status,
    :string,
    :text,
    :time,
    :uuid,
    :video,
    :villain
  ]
  def validate_attr!(type) when type in @valid_attributes, do: true

  def validate_attr!(type),
    do: raise("Unknown type `#{inspect(type)}` given in blueprint")

  def build_attr(name, type, opts \\ []) do
    %{name: name, type: type, opts: opts}
  end

  def build_relation(name, type, opts \\ []) do
    %{name: name, type: type, opts: opts}
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

  defmacro relations(do: block) do
    relations(__CALLER__, block)
  end

  defp relations(_caller, block) do
    quote location: :keep do
      Module.register_attribute(__MODULE__, :relations, accumulate: true)
      unquote(block)
    end
  end

  defmacro relation(name, type, opts \\ []) do
    relation(__CALLER__, name, type, opts)
  end

  defp relation(_caller, name, type, opts) do
    quote location: :keep do
      rel =
        build_relation(
          unquote(name),
          unquote(type),
          unquote(opts)
        )

      Module.put_attribute(__MODULE__, :relations, rel)
    end
  end

  def to_ecto_type(:text), do: :string
  def to_ecto_type(:status), do: Brando.Type.Status
  def to_ecto_type(:image), do: Brando.Type.Image
  def to_ecto_type(:video), do: Brando.Type.Video
  def to_ecto_type(:villain), do: :map
  def to_ecto_type(:slug), do: :string
  def to_ecto_type(:datetime), do: :utc_datetime
  def to_ecto_type(type), do: type
end
