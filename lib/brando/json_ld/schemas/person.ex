defmodule Brando.JSONLD.Schema.Person do
  @moduledoc """
  Person schema
  """

  alias Brando.JSONLD.Schema

  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "Person",
            "@id": nil,
            image: nil,
            name: nil,
            jobTitle: nil,
            email: nil,
            url: nil,
            sameAs: nil,
            worksFor: nil

  @doc """
  Builds a Person from a map of attributes.

  `works_for` accepts a string, which is wrapped as an `@id` reference so the
  person joins the graph rather than duplicating the organization.

  Naming individuals is one of the cheaper ways to answer "who is behind this",
  which search engines and AI crawlers otherwise have to infer from prose.
  """
  @spec build_person(map()) :: %__MODULE__{}
  def build_person(attrs) when is_map(attrs) do
    %__MODULE__{
      "@id": Map.get(attrs, :id),
      name: Map.get(attrs, :name),
      jobTitle: Map.get(attrs, :job_title),
      email: Map.get(attrs, :email),
      url: Map.get(attrs, :url),
      sameAs: attrs |> Map.get(:same_as) |> presence(),
      worksFor: attrs |> Map.get(:works_for) |> reference(),
      image: attrs |> Map.get(:image) |> maybe_image()
    }
  end

  defp maybe_image(nil), do: nil
  defp maybe_image(image), do: Schema.ImageObject.build(image)

  defp reference(nil), do: nil
  defp reference(%{} = org), do: org
  defp reference(id) when is_binary(id), do: %{"@id": id}

  defp presence(nil), do: nil
  defp presence([]), do: nil
  defp presence(list), do: list

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
