defmodule Brando.JSONLD.Schema.HowToStep do
  @moduledoc """
  One step of a recipe's `recipeInstructions`. Google reads its `text`, and
  an optional `name`, `url` and `image`.

      field :recipeInstructions, {:list, JSONLD.Schema.HowToStep}, & &1.steps

  Each item may be the step's text or a map with `:text`, `:name`, `:url`
  and `:image`.
  """

  @derive Jason.Encoder
  defstruct "@type": "HowToStep",
            name: nil,
            text: nil,
            url: nil,
            image: nil

  @spec build(term()) :: %__MODULE__{} | nil
  def build(nil), do: nil
  def build(text) when is_binary(text), do: %__MODULE__{text: text}

  def build(data) when is_map(data) do
    %__MODULE__{
      name: Map.get(data, :name),
      text: Map.get(data, :text),
      url: Map.get(data, :url),
      image: data |> Map.get(:image) |> image()
    }
  end

  defp image(nil), do: nil
  defp image(url) when is_binary(url), do: url
  defp image(image), do: Brando.JSONLD.Schema.ImageObject.build(image)
end
