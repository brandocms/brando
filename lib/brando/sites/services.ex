defmodule Brando.Sites.Services do
  @moduledoc """
  Resolves configured services against their linked entries and builds their
  JSON-LD nodes.

  Resolution happens when the identity cache is (re)built, not on request:
  a linked entry costs one query per service, and the result is stored on the
  cached struct's virtual fields.
  """

  alias Brando.Blueprint.EntryQuery
  alias Brando.Blueprint.Value
  alias Brando.Content.Identifier
  alias Brando.JSONLD.Schema
  alias Brando.Sites.Service
  alias Brando.Type.StringList
  alias Brando.Utils

  @doc """
  Fills `resolved_url` and `resolved_description` from the service's own
  fields, falling back to the linked entry's URL, meta description and
  rendered block text.
  """
  @spec resolve(Service.t()) :: Service.t()
  def resolve(%Service{} = service) do
    identifier = loaded(service.identifier)
    entry = entry_for(identifier)

    %{
      service
      | resolved_url: absolute(presence(service.url) || identifier_url(identifier)),
        resolved_description: presence(service.description) || entry_description(entry)
    }
  end

  @doc "Resolves every service on an identity; tolerates a missing or unloaded list."
  @spec resolve_all(map()) :: map()
  def resolve_all(%{services: services} = identity) when is_list(services) do
    %{identity | services: Enum.map(services, &resolve/1)}
  end

  def resolve_all(identity), do: identity

  @doc """
  Builds one `Service` JSON-LD node per configured service, joined to the
  identity node by reference. A service without its own `area_served`
  inherits the identity's.
  """
  @spec to_json_ld(map()) :: [%Schema.Service{}]
  def to_json_ld(%{services: services} = identity) when is_list(services) do
    hostname = Utils.hostname()
    inherited = identity |> identity_area_served() |> list_or_nil()

    Enum.map(services, fn service ->
      Schema.Service.build(%{
        id: "#{hostname}/#service-#{Utils.slugify(service.name)}",
        name: service.name,
        alternate_names: StringList.normalize(List.wrap(service.alternate_names)),
        description: presence(service.resolved_description) || presence(service.description),
        service_type: presence(service.service_type),
        provider: "#{hostname}/#identity",
        area_served: list_or_nil(service.area_served) || inherited,
        url: presence(service.resolved_url) || absolute(presence(service.url))
      })
    end)
  end

  def to_json_ld(_identity), do: []

  @doc """
  Options for the identity form's service page picker: every identifier with
  a URL, labelled by schema and title.
  """
  @spec identifier_options(term(), term()) :: [%{label: String.t(), value: integer()}]
  def identifier_options(_form, _opts) do
    {:ok, identifiers} = Brando.Content.list_identifiers(%{order: [{:asc, :schema}, {:asc, :title}]})

    identifiers
    |> Enum.reject(&(&1.url in [nil, ""]))
    |> Enum.map(&%{label: "#{Brando.Blueprint.get_singular(&1.schema)}: #{&1.title}", value: &1.id})
  end

  defp identity_area_served(%{type_config: %{area_served: area}}), do: area
  defp identity_area_served(_), do: nil

  defp loaded(%Identifier{} = identifier), do: identifier
  defp loaded(_), do: nil

  defp identifier_url(%Identifier{url: url}), do: presence(url)
  defp identifier_url(_), do: nil

  defp entry_for(%Identifier{schema: schema, entry_id: id}) when is_atom(schema) and not is_nil(id) do
    case EntryQuery.get(schema, id) do
      {:ok, entry} -> entry
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp entry_for(_), do: nil

  defp entry_description(nil), do: nil

  defp entry_description(entry) do
    presence(Map.get(entry, :meta_description)) || Value.rendered_text(entry, length: 300)
  end

  defp absolute(nil), do: nil
  defp absolute("http://" <> _ = url), do: url
  defp absolute("https://" <> _ = url), do: url
  defp absolute(path), do: Utils.hostname(path)

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value) when is_binary(value), do: value
  defp presence(_), do: nil

  defp list_or_nil(nil), do: nil
  defp list_or_nil([]), do: nil
  defp list_or_nil(list) when is_list(list), do: list
  defp list_or_nil(value) when is_binary(value), do: value |> String.split(",") |> StringList.normalize() |> list_or_nil()
end
