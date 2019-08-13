defmodule Brando.JSONLD.Schema.Person do
  @moduledoc """
  Organization schema
  """

  alias Brando.JSONLD.Schema
  alias Brando.Sites

  @derive Jason.Encoder
  defstruct "@context": "http://schema.org",
            "@type": "Person",
            image: nil,
            name: nil

  def build(data) when is_map(data) do
    name = Map.get(data, :name)
    image = Map.get(data, :image)

    if name do
      %__MODULE__{
        name: name,
        image: (image && Schema.ImageObject.build(image)) || nil
      }
    else
      nil
    end
  end

  def build(name) when is_binary(name) do
    %__MODULE__{
      name: name
    }
  end
end
