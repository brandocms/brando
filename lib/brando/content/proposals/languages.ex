defmodule Brando.Content.Proposals.Languages do
  @moduledoc """
  The other language versions of an entry, for the assistant and the review.

  Language versions are linked as alternates. In a synchronized translation
  group (`Brando.Translations`), the source's structure and shared values
  follow to its translations when it is saved — as pending versions with text
  to translate — so a proposal need not repeat those changes there. Other
  versions change only when a proposal changes them.
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Transfer.Catalog
  alias Brando.Repo
  alias Brando.Translations

  @type version :: %{
          language: String.t(),
          content_type: String.t(),
          id: integer(),
          title: String.t(),
          synchronized: boolean()
        }

  @doc """
  `entry`'s other language versions, and its role in a synchronized group:
  `:source`, `:target` or `nil`.
  """
  @spec versions(struct()) :: {atom() | nil, [version()]}
  def versions(%schema{id: id} = entry) when is_integer(id) do
    member = if Translations.synchronized?(schema), do: Translations.get_member(schema, id)
    group = member && Enum.map(Translations.list_members(member.group_id), &{&1.entry_id, &1.synchronized})

    linked =
      entry
      |> alternate_ids()
      |> Enum.concat(for({other, _} <- group || [], other != id, do: other))
      |> Enum.uniq()

    versions = Enum.map(load(schema, linked), &version(&1, schema, member, group))

    {member && member.role, versions}
  rescue
    _ -> {nil, []}
  end

  def versions(_entry), do: {nil, []}

  defp load(_schema, []), do: []
  defp load(schema, ids), do: Repo.all(from(e in schema, where: e.id in ^ids, order_by: [asc: e.language]))

  defp version(other, schema, member, group) do
    %{
      language: to_string(Map.get(other, :language)),
      content_type: Codec.content_type(schema),
      id: other.id,
      title: Catalog.describe(other).title,
      synchronized: synchronized?(member, group, other.id)
    }
  end

  # A version follows the source when both are synchronized members of its group.
  defp synchronized?(%{synchronized: true}, group, id), do: Enum.member?(group, {id, true})
  defp synchronized?(_member, _group, _id), do: false

  defp alternate_ids(%schema{id: id}) do
    if function_exported?(schema, :has_alternates?, 0) and schema.has_alternates?() do
      Repo.all(from(a in Module.concat(schema, Alternate), where: a.entry_id == ^id, select: a.linked_entry_id))
    else
      []
    end
  end
end
