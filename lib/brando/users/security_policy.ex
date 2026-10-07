defmodule Brando.Users.SecurityPolicy do
  @moduledoc """
  The installation's one sign-in policy: who must use two-factor
  authentication. `two_factor` is `:off`, `:everyone`, or `:selected` — the
  users with one of `two_factor_roles`, or, with groups authorization, in one
  of `two_factor_group_ids`. Users are shared by every site, so the policy is
  too. See `Brando.Users.TwoFactor.required?/1`.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Brando.Repo
  alias Brando.Users.SecurityLog

  @type t :: %__MODULE__{}

  @schema_prefix "public"
  @roles ~w(superuser admin editor user)

  schema "users_security_policy" do
    field :two_factor, Ecto.Enum, values: [:off, :everyone, :selected], default: :off
    field :two_factor_roles, {:array, :string}, default: []
    field :two_factor_group_ids, {:array, :integer}, default: []
    belongs_to :updated_by, Brando.Users.User
    timestamps()
  end

  @doc false
  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:two_factor, :two_factor_roles, :two_factor_group_ids])
    |> validate_required([:two_factor])
    |> validate_subset(:two_factor_roles, @roles)
  end

  defp require_enrollment(policy, before_ids) do
    for user <- without_two_factor(policy) do
      Brando.Users.revoke_sessions(user)
      unless MapSet.member?(before_ids, user.id), do: Brando.Users.notify_security(user, :two_factor_required)
    end

    :ok
  end

  defp save(%Ecto.Changeset{data: %{id: nil}} = changeset), do: Repo.insert(changeset)
  defp save(changeset), do: Repo.update(changeset)

  @doc "The roles the policy can name."
  def roles, do: @roles

  @doc """
  The installation's policy, or the default — nobody is required to use two-factor
  authentication — before one is saved.

  Read on every request of a user without two-factor authentication, to
  see whether they must set it up: one single-row query, not cached, so a
  change applies at once on every node.
  """
  @spec get() :: t()
  def get do
    Repo.one(from p in __MODULE__, order_by: [asc: p.id], limit: 1) || %__MODULE__{}
  rescue
    # Before the brando_204 migration has run, nobody is required to use it,
    # and the admin keeps working until it does.
    error in Postgrex.Error ->
      if match?(%{postgres: %{code: :undefined_table}}, error), do: %__MODULE__{}, else: reraise(error, __STACKTRACE__)
  end

  @doc "Whether `policy` requires two-factor authentication of `user`."
  @spec applies?(t(), map()) :: boolean()
  def applies?(%__MODULE__{two_factor: :everyone}, _user), do: true

  def applies?(%__MODULE__{two_factor: :selected} = policy, user) do
    if Brando.Authorization.enabled?(),
      do: member_of_any?(user, policy.two_factor_group_ids),
      else: to_string(Map.get(user, :role)) in policy.two_factor_roles
  end

  def applies?(_policy, _user), do: false

  defp member_of_any?(_user, []), do: false

  defp member_of_any?(%{id: user_id}, group_ids) do
    Repo.repo().exists?(
      from m in Brando.Authorization.Membership, where: m.user_id == ^user_id and m.group_id in ^group_ids
    )
  end

  @doc """
  How many active users `policy` requires two-factor authentication of who
  have not set it up: they set it up at their next sign-in, and their current
  sessions end when the policy is saved.
  """
  @spec without_two_factor_count(t()) :: non_neg_integer()
  def without_two_factor_count(%__MODULE__{} = policy) do
    case without_two_factor_query(policy) do
      nil -> 0
      query -> Repo.aggregate(query, :count)
    end
  end

  @doc "The active users `policy` requires two-factor authentication of who have not set it up."
  @spec without_two_factor(t()) :: [Brando.Users.User.t()]
  def without_two_factor(%__MODULE__{} = policy) do
    case without_two_factor_query(policy) do
      nil -> []
      query -> Repo.all(query)
    end
  end

  defp without_two_factor_query(policy) do
    enrolled = from(s in Brando.Users.Security, where: not is_nil(s.totp_enabled_at), select: s.user_id)

    base =
      from u in Brando.Users.User,
        where: u.active == true and is_nil(u.deleted_at) and u.id not in subquery(enrolled)

    scope_query(base, policy)
  end

  defp scope_query(query, %{two_factor: :everyone}), do: query

  defp scope_query(query, %{two_factor: :selected} = policy) do
    if Brando.Authorization.enabled?() do
      members =
        from m in Brando.Authorization.Membership,
          where: m.group_id in ^policy.two_factor_group_ids,
          select: m.user_id

      from u in query, where: u.id in subquery(members)
    else
      roles = Enum.map(policy.two_factor_roles, &String.to_existing_atom/1)
      from u in query, where: u.role in ^roles
    end
  end

  defp scope_query(_query, _policy), do: nil

  @doc """
  Saves the policy, on behalf of `actor`, who must be a superuser. They must
  have two-factor authentication themselves before a policy that applies to
  them, so that saving it does not end their own session.

  The users it applies to who have not set two-factor authentication up are
  logged out at once (their open admin views are disconnected), and those it
  did not apply to before are emailed that they will set it up at their next
  login.

  Returns `{:ok, policy}`, `{:error, changeset}`, or `{:error, reason}`:
  `:forbidden` or `:enroll_first`.
  """
  @spec update(map(), map(), keyword()) :: {:ok, t()} | {:error, Ecto.Changeset.t() | atom()}
  def update(attrs, actor, opts \\ []) do
    policy = get()
    changeset = policy |> changeset(attrs) |> put_change(:updated_by_id, actor.id)

    cond do
      not Brando.Users.superuser?(actor) ->
        {:error, :forbidden}

      not changeset.valid? ->
        {:error, changeset}

      applies?(apply_changes(changeset), actor) and not Brando.Users.TwoFactor.enabled?(actor) ->
        {:error, :enroll_first}

      true ->
        before_ids = policy |> without_two_factor() |> MapSet.new(& &1.id)

        with {:ok, saved} <- save(changeset) do
          require_enrollment(saved, before_ids)

          SecurityLog.record(:policy_changed, actor,
            actor: actor,
            meta: opts[:meta],
            details: %{
              "two_factor" => to_string(saved.two_factor),
              "roles" => saved.two_factor_roles,
              "group_ids" => saved.two_factor_group_ids
            }
          )

          {:ok, saved}
        end
    end
  end
end
