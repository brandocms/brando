defmodule Brando.Content.Definitions.Release.Preview do
  @moduledoc """
  An entry's page as it is and as the release's module definitions would
  render it, side by side in the reviewer's browser: each is a live preview
  (`Brando.LivePreview`), rendered by the site's own preview target, and
  nothing is saved. `share/4` makes a `Brando.Sites.Preview` link of the
  proposed page, for someone without an admin account.

  The pages carry the block markers live previews do, so the screen outlines
  the blocks that differ (`livepreview_highlight.js`).
  """

  alias Brando.Authorization.Boundary
  alias Brando.Content.Definitions.Release.{Proposed, Verify}
  alias Brando.LivePreview
  alias Brando.Villain

  @doc """
  Renders entry `id` of `schema` both ways for `user`, who must be able to
  read it. Returns `{:ok, %{before: key, after: key | {:error, message},
  marks: [%{uid, kind, label}]}}`, where `kind` is `"changed"` or `"failed"`,
  or `{:error, reason}`: `:no_preview_target` when the content type has no
  preview target.
  """
  def render(proposed, schema, id, user) do
    with true <- LivePreview.has_live_preview_target(schema) || {:error, :no_preview_target},
         :ok <- Boundary.authorize_record(user, :read, schema, id),
         {:ok, entry} <- Brando.Blueprint.EntryQuery.get(schema, id),
         {:ok, blocks} <- Verify.blocks(schema, id, proposed),
         {:ok, before} <- initialize(Ecto.Changeset.change(entry), user) do
      after_key =
        case Villain.with_modules(proposed.modules, fn ->
               initialize(proposed_changeset(schema, entry, proposed), user)
             end) do
          {:ok, key} -> key
          {:error, message} -> {:error, message}
        end

      {:ok, %{before: before, after: after_key, marks: marks(blocks)}}
    else
      {:error, _} = error -> error
      _ -> {:error, :forbidden}
    end
  end

  @doc "Forgets the previews `render/4` made."
  def discard(%{before: before, after: after_key}) do
    LivePreview.cleanup_cache(before)
    if is_binary(after_key), do: LivePreview.cleanup_cache(after_key)
    :ok
  end

  def discard(_), do: :ok

  @doc """
  A shared preview link of entry `id` of `schema` as the release would
  render it. Returns `{:ok, url, expiry_days}` or `{:error, reason}`.
  """
  def share(proposed, schema, id, user) do
    with :ok <- Boundary.authorize_record(user, :read, schema, id),
         {:ok, entry} <- Brando.Blueprint.EntryQuery.get(schema, id) do
      scope = Boundary.actor_scope(user)
      user = Brando.Repo.get!(Brando.Users.User, user.id)
      changeset = proposed_changeset(schema, entry, proposed)

      Boundary.with_scope(scope, fn ->
        Villain.with_modules(proposed.modules, fn -> LivePreview.share(schema, changeset, user, %{}, nil) end)
      end)
    end
  end

  # The entry with its blocks synced to the proposed modules, as applying
  # them would leave them
  defp proposed_changeset(schema, entry, proposed) do
    entry =
      Enum.reduce(schema.__blocks_fields__(), entry, fn field, entry ->
        key = :"entry_#{field.name}"
        Map.update!(entry, key, &Proposed.sync_entry_blocks(&1, proposed))
      end)

    Ecto.Changeset.change(entry)
  end

  defp initialize(changeset, user) do
    scope = Boundary.actor_scope(user)
    Boundary.with_scope(scope, fn -> LivePreview.initialize(changeset.data.__struct__, changeset, %{}, nil) end)
  end

  defp marks(blocks) do
    for %{state: state} = block <- blocks, state in [:changed, :failed] do
      %{uid: block.uid, kind: if(state == :failed, do: "failed", else: "changed"), label: block.module}
    end
  end
end
