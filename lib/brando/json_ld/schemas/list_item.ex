defmodule Brando.JSONLD.Schema.ListItem do
  @moduledoc false
  @derive Jason.Encoder
  defstruct "@type": "ListItem",
            position: nil,
            name: nil,
            item: nil

  def build(position, name, nil) do
    %__MODULE__{
      position: position,
      name: name
    }
  end

  def build(position, name, item) do
    %__MODULE__{
      position: position,
      name: name,
      item: Brando.Utils.hostname(item)
    }
  end
end
