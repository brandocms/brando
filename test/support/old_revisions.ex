defmodule Brando.OldRevisions do
  @moduledoc """
  Revisions as Brando stored them before blocks had a `module_version`
  (2026-09-05) and a `sync_uid` (2026-09-24). A revision is a
  `term_to_binary` snapshot of the entry, so its block and table row structs
  lack those keys entirely, and dot access on them raises.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.TableRow
  alias Brando.Repo
  alias Brando.Revisions.Revision

  @doc "Rewrite a stored revision as one from before those keys existed."
  def forget_block_identity!(entry, revision_number) do
    query =
      from(r in Revision,
        where: r.entry_type == ^to_string(entry.__struct__) and r.entry_id == ^entry.id and r.revision == ^revision_number
      )

    encoded = Repo.one!(from(r in query, select: r.encoded_entry))
    old = encoded |> :erlang.binary_to_term() |> forget() |> Brando.Utils.term_to_binary()
    {1, _} = Repo.update_all(query, set: [encoded_entry: old])
    :ok
  end

  defp forget(%{__struct__: mod} = struct) when mod in [Block, TableRow],
    do: struct |> Map.drop([:module_version, :sync_uid]) |> forget_values()

  defp forget(%{__meta__: _} = struct), do: forget_values(struct)
  defp forget(list) when is_list(list), do: Enum.map(list, &forget/1)
  defp forget(other), do: other

  defp forget_values(struct), do: struct |> Map.to_list() |> Map.new(fn {key, value} -> {key, forget(value)} end)
end
