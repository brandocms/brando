defmodule Brando.JSONLD.Schema.ListItem do
  @derive Jason.Encoder
  defstruct "@type": "ListItem",
            position: nil,
            name: nil,
            item: nil

  def build(position, name, item) do
    %__MODULE__{
      position: position,
      name: name,
      item: item
    }
  end
end
