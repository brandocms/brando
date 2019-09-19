defmodule Brando.JSONLD.Schema.Person do
  @moduledoc """
  Person schema
  """

  alias Brando.JSONLD.Schema

  @derive Jason.Encoder
  defstruct "@context": "http://schema.org",
            "@type": "Person",
            image: nil,
            name: nil

  def build(data) when is_map(data) do
    name = Map.get(data, :name)
    image = Map.get(data, :image)

    %__MODULE__{
      name: name,
      image: (image && Schema.ImageObject.build(image)) || nil
    }
  end

  def build(nil) do
    %__MODULE__{}
  end

  def build(name) when is_binary(name) do
    %__MODULE__{
      name: name
    }
  end
end
