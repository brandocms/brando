defmodule Brando.Pages.Page.PreventParentCycles do
  @moduledoc """
  Refuses a page's parent that is the page itself or a page under it.
  """
  use Brando.Trait
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset

  def changeset_mutator(_module, _config, %Changeset{data: %{id: id}, changes: %{parent_id: parent_id}} = changeset, _, _)
      when not is_nil(id) and not is_nil(parent_id) do
    if under_page?(changeset.data, parent_id, MapSet.new()) do
      Changeset.add_error(changeset, :parent_id, gettext("can't be the page itself or a page under it"))
    else
      changeset
    end
  end

  def changeset_mutator(_module, _config, changeset, _user, _opts), do: changeset

  # Walks up from `page_id` to the top. A cycle already stored ends the walk.
  defp under_page?(%{id: id}, id, _seen), do: true
  defp under_page?(_page, nil, _seen), do: false

  defp under_page?(%schema{} = page, page_id, seen) do
    if MapSet.member?(seen, page_id) do
      false
    else
      parent_id = Brando.Repo.one(from(p in schema, where: p.id == ^page_id, select: p.parent_id), prefix_opts(page))
      under_page?(page, parent_id, MapSet.put(seen, page_id))
    end
  end

  defp prefix_opts(page) do
    case Ecto.get_meta(page, :prefix) do
      prefix when is_binary(prefix) -> [prefix: prefix]
      _ -> []
    end
  end
end
