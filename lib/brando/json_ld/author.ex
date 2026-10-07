defmodule Brando.JSONLD.Author do
  @moduledoc """
  Builds `Person` nodes for the `:person` field type of the blueprint
  `json_ld_schema` DSL — an entry's author, editor or contributors:

      json_ld_schema JSONLD.Schema.Article do
        field :author, :person, & &1.creator
      end

  The callback returns a Brando user, an entry of a People blueprint, a name,
  or a list of them; anything not loaded is skipped. Each becomes a `Person`
  with a stable `@id`, which `Brando.JSONLD.to_graph_json/1` lifts into the
  page's `@graph` and replaces with a reference.

  ## Brando users

  A user gives only public profile fields: `name`, `job_title` (`jobTitle`),
  `same_as` (`sameAs`, the profile URLs) and the `avatar` (`image`, when
  preloaded). Never the email, role or anything else. Users have no public
  page, so their `@id` is `https://example.com/#/schema/person/<hash>`, a
  hash of the user id.

  ## People entries

  An entry whose blueprint declares a `json_ld_schema` of `@type` Person is
  built through that mapping, so the author on an article and the person on
  their own profile page are the same node: both get the `@id`
  `<the entry's absolute URL>/#person`. Without such a mapping the entry is
  read by convention: `name` (or the identifier's title), `job_title`,
  `same_as`, and the first preloaded image of `avatar`, `portrait`, `image`
  or `photo`.
  """

  alias Brando.Images.Image
  alias Brando.JSONLD
  alias Brando.JSONLD.Schema.Person
  alias Brando.Users.User
  alias Brando.Utils

  @image_fields [:avatar, :portrait, :image, :photo]

  @doc """
  Builds a `Person`, or a list of them for a list. `nil` for nothing, and for
  values that are not loaded.
  """
  @spec build(term()) :: Person.t() | [Person.t()] | nil
  def build(values) when is_list(values) do
    case values |> Enum.map(&person/1) |> Enum.reject(&is_nil/1) |> Enum.uniq_by(&uniq_key/1) do
      [] -> nil
      people -> people
    end
  end

  def build(value), do: person(value)

  @doc "The `@id` of a user's `Person` node."
  @spec user_id(User.t()) :: String.t()
  def user_id(%User{id: id}) do
    hash = :sha256 |> :crypto.hash("brando-user:#{id}") |> Base.encode16(case: :lower) |> binary_part(0, 16)
    Path.join(Utils.hostname(), "#/schema/person/#{hash}")
  end

  defp person(nil), do: nil
  defp person(%Ecto.Association.NotLoaded{}), do: nil

  defp person(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      name -> %Person{name: name}
    end
  end

  defp person(%User{name: name} = user) when is_binary(name) and name != "" do
    %Person{
      "@id": user_id(user),
      name: name,
      jobTitle: present(Map.get(user, :job_title)),
      sameAs: list(Map.get(user, :same_as)),
      image: image(user.avatar)
    }
  end

  defp person(%User{}), do: nil

  defp person(%{__struct__: module} = entry) do
    url = absolute_url(module, entry)

    case from_schema(module, entry, url) do
      %{"@type": "Person"} = node -> node
      _ -> by_convention(module, entry, url)
    end
  end

  defp person(_value), do: nil

  # The People blueprint's own mapping, as on the entry's profile page.
  defp from_schema(module, entry, url) do
    if function_exported?(module, :spark_dsl_config, 0) do
      meta = %{current_url: url, language: Map.get(entry, :language)}

      module
      |> JSONLD.extract_json_ld(Map.put(entry, :__meta__, meta))
      |> put_identity(module, entry, url)
    end
  end

  defp put_identity(%{"@type": "Person"} = node, module, entry, url) do
    node = Map.put(node, :"@id", node_id(module, entry, url))

    if Map.has_key?(node, :url) and is_nil(node.url), do: %{node | url: url}, else: node
  end

  defp put_identity(node, _module, _entry, _url), do: node

  defp by_convention(module, entry, url) do
    case name(module, entry) do
      nil ->
        nil

      name ->
        %Person{
          "@id": node_id(module, entry, url),
          name: name,
          url: url,
          jobTitle: present(Map.get(entry, :job_title)),
          sameAs: list(Map.get(entry, :same_as)),
          image: Enum.find_value(@image_fields, &image(Map.get(entry, &1)))
        }
    end
  end

  defp node_id(_module, _entry, url) when is_binary(url), do: Path.join(url, "#person")

  defp node_id(module, %{id: id}, nil) when not is_nil(id) do
    hash = :sha256 |> :crypto.hash("#{inspect(module)}:#{id}") |> Base.encode16(case: :lower) |> binary_part(0, 16)
    Path.join(Utils.hostname(), "#/schema/person/#{hash}")
  end

  defp node_id(_module, _entry, _url), do: nil

  defp name(module, entry) do
    present(Map.get(entry, :name)) || identifier_title(module, entry) || present(Map.get(entry, :title))
  end

  defp identifier_title(module, entry) do
    if function_exported?(module, :__has_identifier__, 0) and module.__has_identifier__() do
      entry |> module.__identifier__(skip_cover: true) |> Map.get(:title) |> present()
    end
  rescue
    _ -> nil
  end

  defp absolute_url(module, entry) do
    with true <- function_exported?(module, :__has_absolute_url__, 0),
         true <- module.__has_absolute_url__(),
         url when is_binary(url) and url != "" <- module.__absolute_url__(entry) do
      absolute(url)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp absolute("http://" <> _ = url), do: url
  defp absolute("https://" <> _ = url), do: url
  defp absolute(path), do: Utils.hostname(path)

  defp image(%Image{} = image), do: JSONLD.Schema.ImageObject.build(image)
  defp image(_image), do: nil

  defp list(values) when is_list(values) do
    case values |> Enum.filter(&is_binary/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) do
      [] -> nil
      values -> values
    end
  end

  defp list(_values), do: nil

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present(_value), do: nil

  defp uniq_key(%{"@id": nil, name: name}), do: {:name, name}
  defp uniq_key(%{"@id": id}), do: id
end
