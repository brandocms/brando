defmodule Brando.Content.Proposals.Preview do
  use Gettext, backend: Brando.Gettext
  import Ecto.Query, only: [from: 2]

  @moduledoc """
  Private page previews of a proposal, rendered by the site's own live-preview
  targets.

  `render/4` renders one target of a proposal either as proposed or as its
  saved baseline (`version: :before`). The entry is materialized in memory
  from the proposal — nothing is saved — and rendered through
  `Brando.LivePreview.initialize/4`, which registers the preview key under the
  proposing user's authorization scope. A translation the proposal creates
  is made and rendered in a transaction that is rolled back
  (`Proposals.with_translation/5`). Keys are random, so they never
  collide with an editor's preview. Call `discard/1` with the returned keys
  when the proposal is replaced, cancelled or applied.
  """
  alias Brando.Authorization.Boundary
  alias Brando.Content.Proposals
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.Error
  alias Brando.LivePreview
  alias Brando.Repo

  @doc """
  Render `target` of `proposal`.

  Options:

    * `:version` — `:proposed` (default) or `:before`
    * `:preview_target` — a named `preview_target`; the schema's default otherwise
    * `:shared` — rendered for a colleague the proposal was shared with, who
      needs only to be able to read its entries

  Returns `{:ok, %{key: key, html: html}}`, `{:error, :not_created}` for the
  baseline of an entry the proposal creates, `{:error, :no_preview_target}`
  when the content type has no preview target, `{:error, :problems}` for the
  proposed version of a proposal with problems (`Proposals.previewable?/1`),
  or `{:error, message}`.
  """
  @spec render(Proposals.Proposal.t(), Proposals.Proposal.target(), term(), keyword()) ::
          {:ok, %{key: String.t(), html: String.t()}} | {:error, atom() | String.t()}
  def render(proposal, target, actor, opts \\ []) do
    version = Keyword.get(opts, :version, :proposed)

    copy? = version == :proposed and Proposals.translation(proposal.operations, target) != nil
    initialize = &initialize(&1, actor, opts[:preview_target], copy?)

    with :ok <- renderable(proposal, target, version),
         {:ok, key} <- with_changeset(proposal, target, actor, version, opts[:shared], opts[:preview_target], initialize) do
      {:ok, html} = LivePreview.get_cache(key)
      {:ok, %{key: key, html: html}}
    end
  end

  @doc """
  Render entry `id` of `schema` as it is saved, for an editor reviewing a
  proposal: a draft has no public page to open. The editor must be able to
  read the entry. Returns `{:ok, key}`, `{:error, :no_preview_target}` or
  `{:error, message}`.
  """
  @spec render_saved(module(), integer(), term()) :: {:ok, String.t()} | {:error, atom() | String.t()}
  def render_saved(schema, id, actor) do
    with true <- LivePreview.has_live_preview_target(schema) || {:error, :no_preview_target},
         {:ok, entry} <- Error.protect(fn -> Brando.Content.Transfer.Catalog.load!(schema, id, actor, :read) end) do
      entry |> Ecto.Changeset.change() |> initialize(actor, nil, false)
    end
  end

  @doc "Remove the rendered HTML, cached assigns and authority of preview keys."
  @spec discard([String.t()]) :: :ok
  def discard(keys), do: Enum.each(keys, &LivePreview.cleanup_cache/1)

  # A proposal with problems is not rendered: the preview runs in the
  # reviewer's browser before anyone approves it, and text the checks could
  # not reach may be in it.
  defp renderable(proposal, target, version) do
    schema =
      case target do
        {:new, _} -> Map.get(proposal.targets, target)
        {schema, _} -> Map.has_key?(proposal.targets, target) && schema
      end

    cond do
      !schema -> {:error, dgettext("content_proposals", "This entry is not part of the proposal.")}
      version == :before and match?({:new, _}, target) -> {:error, :not_created}
      !LivePreview.has_live_preview_target(schema) -> {:error, :no_preview_target}
      version == :proposed and not Proposals.previewable?(proposal) -> {:error, :problems}
      true -> :ok
    end
  end

  # `fun` with the target's changeset. A translation the proposal creates
  # exists only inside the transaction `Proposals.with_translation/5` rolls
  # back, so `fun` renders it there.
  defp with_changeset(proposal, target, actor, version, shared, preview_target, fun) do
    if version == :proposed and Proposals.translation(proposal.operations, target),
      do: with_copy(proposal, target, actor, shared, preview_target, fun),
      else:
        with(
          {:ok, changeset} <- changeset(proposal, target, actor, version, shared, preview_target),
          do: fun.(changeset)
        )
  end

  # The copy as the page reads an entry (`page_entry/2`), in the transaction
  defp with_copy(proposal, target, actor, shared, preview_target, fun) do
    Proposals.with_translation(proposal, target, actor, [shared: !!shared], fn changeset ->
      changeset |> Brando.Utils.apply_changes_recursively() |> page_entry(preview_target) |> fun.()
    end)
  end

  defp changeset(proposal, target, actor, :proposed, shared, preview_target) do
    with {:ok, changesets} <- Proposals.materialize(proposal, actor, shared: !!shared) do
      entry = changesets |> Map.fetch!(target) |> Brando.Utils.apply_changes_recursively()
      {:ok, page_entry(entry, preview_target)}
    end
  end

  defp changeset(proposal, target, actor, :before, shared, preview_target) do
    Error.protect(fn ->
      unless shared, do: Proposals.authorize_proposal!(proposal, actor)

      proposal
      |> Proposals.current!(actor, if(shared, do: :read, else: :update))
      |> Map.fetch!(target)
      |> page_entry(preview_target)
    end)
  end

  # The entry is loaded with its blocks only, and the page reads it as a
  # saved one is read: its media (the head's meta image), relations and
  # alternates. They load after the proposal's changes apply, so a media
  # field it changes shows its new picture; a list it sets keeps its rows,
  # which get what they read (an entries list's identifiers). What the
  # preview target's own `schema_preloads` names is loaded by its query
  # first, which may pick fewer rows (published children only); those rows
  # then get what the Blueprint loads beneath them (a gallery's objects).
  defp page_entry(entry, preview_target) do
    entry =
      entry.__struct__
      |> target_preloads(preview_target)
      |> Enum.reject(&Ecto.assoc_loaded?(Map.get(entry, preload_name(&1))))
      |> then(&Repo.preload(entry, &1))

    {loaded, unloaded} =
      entry.__struct__
      |> Brando.Blueprint.preloads_for(skip_blocks: true)
      |> Enum.split_with(&Ecto.assoc_loaded?(Map.get(entry, preload_name(&1))))

    # On the loaded rows, not through the entry: Ecto refuses a loaded list
    # on an entry without an id, as a new one is
    loaded
    |> Enum.reduce(entry, fn preload, entry ->
      Map.update!(entry, preload_name(preload), &Repo.preload(&1, nested(preload)))
    end)
    |> Repo.preload(unloaded)
    |> Ecto.Changeset.change()
  end

  defp target_preloads(schema, preview_target) do
    schema |> LivePreview.get_target_config(preview_target) |> Map.fetch!(:schema_preloads)
  rescue
    # An unknown target fails where the preview renders
    Brando.Exception.LivePreviewError -> []
  end

  defp preload_name({name, _nested}), do: name
  defp preload_name(name), do: name

  defp nested({_name, %Ecto.Query{preloads: preloads}}), do: preloads
  defp nested({_name, preloads}), do: preloads
  defp nested(_name), do: []

  @doc """
  A public link to the proposed page, for any browser: a static snapshot
  rendered by the site's own template, as the editor's "Get shareable link"
  makes. Anyone with the link can view it until it expires; it takes the
  export permission, and a stored proposal a review link could still show.
  Returns `{:ok, url, expiry_days}`, or `{:error, reason}` as `render/4` does.
  """
  @spec share(Proposals.Proposal.t(), Proposals.Proposal.target(), term(), keyword()) ::
          {:ok, String.t(), integer()} | {:error, atom() | String.t()}
  def share(proposal, target, actor, opts \\ []) do
    with :ok <- renderable(proposal, target, :proposed),
         :ok <- shown(proposal),
         {:ok, changeset} <- to_share(proposal, target, actor, opts[:shared], opts[:preview_target]) do
      scope = Boundary.actor_scope(actor)
      user = Repo.get!(Brando.Users.User, scope.user_id)

      Boundary.with_scope(scope, fn ->
        LivePreview.share(target_schema(proposal, target), changeset, user, %{}, opts[:preview_target])
      end)
    end
  end

  @doc """
  A public link to one target's page of `proposal`, for the connected AI
  tool that prepared it (`preview_proposal`): a static snapshot stored as
  `share/4`'s is, with the proposal version it shows, which lives 15 minutes
  and opens only while that version is under review
  (`Brando.LivePreview.share_proposal/5`). Nothing is saved but the
  snapshot.

  It checks what the admin's own review preview checks for `actor`, for
  both versions: that the actor prepared it here, may edit its existing
  entries as they are, and may edit the entry as the proposal leaves it (or
  create it, for a new entry). The export permission `share/4` takes is
  not.

  Options: `:version` (`:proposed`, the default, or `:before`) and
  `:preview_target`, as `render/4` takes them. Returns
  `{:ok, url, expires_at}`, or the errors `render/4` returns, or
  `{:error, message}` for a preview target the content type does not have.
  """
  @spec snapshot(Proposals.Proposal.t(), Proposals.Proposal.target(), term(), keyword()) ::
          {:ok, String.t(), DateTime.t()} | {:error, atom() | String.t()}
  def snapshot(proposal, target, actor, opts \\ []) do
    version = Keyword.get(opts, :version, :proposed)

    with :ok <- renderable(proposal, target, version),
         {:ok, preview_target} <- preview_target(proposal, target, opts[:preview_target]),
         {:ok, changeset} <- to_snapshot(proposal, target, actor, version, preview_target) do
      scope = Boundary.actor_scope(actor)
      user = Repo.get!(Brando.Users.User, scope.user_id)

      Boundary.with_scope(scope, fn ->
        LivePreview.share_proposal(target_schema(proposal, target), changeset, user, proposal.id, preview_target)
      end)
    end
  end

  # What a stored snapshot renders (`LivePreview.share/5`): the changeset, or
  # for a translation the proposal creates a builder that makes it and
  # renders it in the transaction it rolls back. Creating the copy takes the
  # permission to create it.
  defp to_share(proposal, target, actor, shared, preview_target) do
    if Proposals.translation(proposal.operations, target),
      do: {:ok, &with_copy(proposal, target, actor, shared, preview_target, &1)},
      else: changeset(proposal, target, actor, :proposed, shared, preview_target)
  end

  defp to_snapshot(proposal, target, actor, version, preview_target) do
    if Proposals.translation(proposal.operations, target),
      do: to_share(proposal, target, actor, nil, preview_target),
      else: existing_snapshot(proposal, target, actor, version, preview_target)
  end

  defp existing_snapshot(proposal, target, actor, version, preview_target) do
    with {:ok, proposed} <- changeset(proposal, target, actor, :proposed, nil, preview_target),
         :ok <- authorize_snapshot(actor, proposed) do
      if version == :before,
        do: changeset(proposal, target, actor, :before, nil, preview_target),
        else: {:ok, proposed}
    end
  end

  # A name the content type's live preview declares, or nil for its default
  defp preview_target(_proposal, _target, nil), do: {:ok, nil}

  defp preview_target(proposal, target, name) do
    names = proposal |> target_schema(target) |> LivePreview.get_targets() |> Enum.map(&to_string(&1.name))

    if to_string(name) in names,
      do: {:ok, String.to_existing_atom(to_string(name))},
      else:
        {:error,
         dgettext("content_proposals", "Unknown preview target %{name}. This content type has: %{names}.",
           name: inspect(name),
           names: Enum.join(names, ", ")
         )}
  end

  defp target_schema(proposal, {:new, _} = target), do: Map.fetch!(proposal.targets, target)
  defp target_schema(_proposal, {schema, _id}), do: schema

  defp authorize_snapshot(actor, changeset) do
    case Brando.Authorization.Preview.authorize_snapshot(actor, changeset) do
      :ok ->
        :ok

      {:error, :forbidden} ->
        {:error, dgettext("content_proposals", "You may not edit this entry as the proposal leaves it.")}
    end
  end

  # The proposal on screen may have been discarded in another tab, or have
  # expired, since it was read: its stored status and deadline decide, as
  # for `Proposals.get_shared/3`.
  defp shown(%{id: id}) do
    stored =
      id &&
        Repo.one(
          from(r in Proposals.Record,
            where: r.id == ^id and r.scope == ^Transfer.scope(),
            select: {r.status, r.expires_at}
          )
        )

    case stored do
      {"applied", _} ->
        :ok

      {status, expires_at} when status in ~w(pending approved) ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt,
          do: :ok,
          else: {:error, dgettext("content_proposals", "This proposal has expired. Prepare it again.")}

      _ ->
        {:error, dgettext("content_proposals", "This proposal is no longer under review.")}
    end
  end

  # A copy's key is registered again as a new entry's: the copy is gone once
  # rolled back, and its frame is authorized by the permission to create it,
  # as a new entry's is.
  defp initialize(changeset, actor, preview_target, copy?) do
    scope = Boundary.actor_scope(actor)

    Boundary.with_scope(scope, fn ->
      changeset.data.__struct__
      |> LivePreview.initialize(changeset, %{}, preview_target)
      |> register_new(changeset, copy?)
    end)
  end

  defp register_new(result, _changeset, false), do: result
  defp register_new({:error, _} = error, _changeset, true), do: error

  defp register_new({:ok, key}, changeset, true) do
    entry = Ecto.Changeset.apply_changes(changeset)

    case Brando.Authorization.Preview.register(key, Ecto.Changeset.change(%{entry | id: nil})) do
      :ok ->
        {:ok, key}

      {:error, :forbidden} ->
        LivePreview.cleanup_cache(key)
        {:error, :forbidden}
    end
  end
end
