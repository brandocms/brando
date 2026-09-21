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
      item: absolute(item)
    }
  end

  # Breadcrumbs pass paths; collections pass URLs that already carry the host.
  defp absolute("http://" <> _ = url), do: url
  defp absolute("https://" <> _ = url), do: url
  defp absolute(path), do: Brando.Utils.hostname(path)
end
