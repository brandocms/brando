defmodule Brando.Content.Proposals.Preview do
  use Gettext, backend: Brando.Gettext

  @moduledoc """
  Private page previews of a proposal, rendered by the site's own live-preview
  targets.

  `render/4` renders one target of a proposal either as proposed or as its
  saved baseline (`version: :before`). The entry is materialized in memory
  from the proposal — nothing is saved — and rendered through
  `Brando.LivePreview.initialize/4`, which registers the preview key under the
  proposing user's authorization scope. Keys are random, so they never
  collide with an editor's preview. Call `discard/1` with the returned keys
  when the proposal is replaced, cancelled or applied.
  """
  alias Brando.Authorization.Boundary
  alias Brando.Content.Proposals
  alias Brando.Content.Transfer.Error
  alias Brando.LivePreview

  @doc """
  Render `target` of `proposal`.

  Options:

    * `:version` — `:proposed` (default) or `:before`
    * `:preview_target` — a named `preview_target`; the schema's default otherwise
    * `:shared` — rendered for a colleague the proposal was shared with, who
      needs only to be able to read its entries

  Returns `{:ok, %{key: key, html: html}}`, `{:error, :not_created}` for the
  baseline of an entry the proposal creates, `{:error, :no_preview_target}`
  when the content type has no preview target, or `{:error, message}`.
  """
  @spec render(Proposals.Proposal.t(), Proposals.Proposal.target(), term(), keyword()) ::
          {:ok, %{key: String.t(), html: String.t()}} | {:error, atom() | String.t()}
  def render(proposal, target, actor, opts \\ []) do
    version = Keyword.get(opts, :version, :proposed)

    with :ok <- renderable(proposal, target, version),
         {:ok, changeset} <- changeset(proposal, target, actor, version, opts[:shared]),
         {:ok, key} <- initialize(changeset, actor, opts[:preview_target]) do
      {:ok, html} = LivePreview.get_cache(key)
      {:ok, %{key: key, html: html}}
    end
  end

  @doc "Remove the rendered HTML, cached assigns and authority of preview keys."
  @spec discard([String.t()]) :: :ok
  def discard(keys), do: Enum.each(keys, &LivePreview.cleanup_cache/1)

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
      true -> :ok
    end
  end

  defp changeset(proposal, target, actor, :proposed, shared) do
    with {:ok, changesets} <- Proposals.materialize(proposal, actor, shared: !!shared),
         do: {:ok, Map.fetch!(changesets, target)}
  end

  defp changeset(proposal, target, actor, :before, shared) do
    Error.protect(fn ->
      unless shared, do: Proposals.authorize_proposal!(proposal, actor)

      proposal
      |> Proposals.current!(actor, if(shared, do: :read, else: :update))
      |> Map.fetch!(target)
      |> Ecto.Changeset.change()
    end)
  end

  @doc """
  A public link to the proposed page, for any browser: a static snapshot
  rendered by the site's own template, as the editor's "Get shareable link"
  makes. Anyone with the link can view it until it expires; it takes the
  export permission. Returns `{:ok, url, expiry_days}`.
  """
  @spec share(Proposals.Proposal.t(), Proposals.Proposal.target(), term(), keyword()) ::
          {:ok, String.t(), integer()} | {:error, atom() | String.t()}
  def share(proposal, target, actor, opts \\ []) do
    with :ok <- renderable(proposal, target, :proposed),
         {:ok, changeset} <- changeset(proposal, target, actor, :proposed, opts[:shared]) do
      scope = Boundary.actor_scope(actor)
      user = Brando.Repo.get!(Brando.Users.User, scope.user_id)

      Boundary.with_scope(scope, fn ->
        LivePreview.share(changeset.data.__struct__, changeset, user, %{}, opts[:preview_target])
      end)
    end
  end

  defp initialize(changeset, actor, preview_target) do
    scope = Boundary.actor_scope(actor)

    Boundary.with_scope(scope, fn ->
      LivePreview.initialize(changeset.data.__struct__, changeset, %{}, preview_target)
    end)
  end
end
