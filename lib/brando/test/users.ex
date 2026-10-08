defmodule Brando.Test.Users do
  @moduledoc """
  Users with given rights, and logging them in to the admin. Imported by
  `use Brando.Test`; see `Brando.Test`.

  Brando authorizes in one of two modes (see the authorization guide):

    * **legacy roles** — `role: :user | :editor | :admin | :superuser`, checked
      against the rules in your `Brando.Authorization` module;
    * **groups** (`config :brando, authorization_mode: :groups`) — permission
      keys such as `"my_app.projects.update"`, granted through groups.

  `insert_user/1` takes either: `role:` sets the legacy role, `permissions:`
  puts the user in a group with exactly those permissions.

      user = insert_user(role: :editor)
      user = insert_user(permissions: ["brando.admin.access", "my_app.projects.read", "my_app.projects.update"])
      {conn, user} = log_in_as(conn, permissions: ["my_app.projects.read"])
  """

  alias Brando.Authorization.{Catalog, Grant, Group, Membership, Scope}
  alias Brando.Users.{User, UserConfig}

  @password "brandocms"

  @doc """
  Insert an admin user. `attrs` sets fields on `Brando.Users.User`
  (`role:` defaults to `:superuser`, the password is `"#{@password}"`), and
  `permissions:` grants permission keys through a group of their own (groups
  mode only; the role then defaults to `:user`).
  """
  @spec insert_user(keyword() | map()) :: User.t()
  def insert_user(attrs \\ []) do
    {permissions, attrs} = attrs |> Map.new() |> Map.pop(:permissions)
    n = System.unique_integer([:positive])

    user =
      Brando.Repo.repo().insert!(
        struct!(
          User,
          Map.merge(
            %{
              name: "Test User #{n}",
              email: "user-#{n}@example.com",
              password: Bcrypt.hash_pwd_salt(@password),
              role: if(permissions, do: :user, else: :superuser),
              language: :en,
              config: %UserConfig{}
            },
            attrs
          )
        )
      )

    if permissions, do: grant_permissions(user, permissions)
    user
  end

  @doc """
  Grant `permissions` to `user` through a new group in the current scope.
  Raises outside groups mode, and for keys the permission catalogue does not
  have, listing them.
  """
  @spec grant_permissions(User.t(), [String.t()]) :: struct()
  def grant_permissions(%User{} = user, permissions) do
    unless Brando.Authorization.enabled?() do
      raise ArgumentError,
            "permissions are granted in groups mode (config :brando, authorization_mode: :groups); " <>
              "in legacy mode give the user a role: insert_user(role: :editor)"
    end

    known = MapSet.new(Catalog.all(), & &1.key)
    unknown = Enum.reject(permissions, &MapSet.member?(known, &1))
    if unknown != [], do: raise(ArgumentError, "unknown permission keys: #{inspect(unknown)}")

    repo = Brando.Repo.repo()
    scope = Scope.current(user)
    n = System.unique_integer([:positive])

    group =
      repo.insert!(%Group{
        key: "test-group-#{n}",
        name: "Test group #{n}",
        scope_kind: scope.kind,
        site_id: scope.site_id
      })

    Enum.each(Enum.uniq(permissions), &repo.insert!(%Grant{group_id: group.id, permission_key: &1}))
    repo.insert!(%Membership{user_id: user.id, group_id: group.id})
    group
  end

  @doc """
  Put a session for `user` on `conn`, as logging in does, so admin
  LiveViews mount for them.

  Not the admin's own log-in function: that one ends in a redirect, so
  it returns a sent conn that `live/2` cannot use. The admin reads the
  session, and this writes what logging in writes.
  """
  @spec log_in_user(Plug.Conn.t(), User.t()) :: Plug.Conn.t()
  def log_in_user(conn, %User{} = user) do
    token = Brando.Users.generate_user_session_token(user)

    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
    |> Plug.Conn.put_session(:live_socket_id, Brando.Users.live_socket_id(token))
  end

  @doc """
  Insert a user with `attrs` (see `insert_user/1`) and log them in. In groups
  mode, `"brando.admin.access"` is added to `permissions:`, since nobody
  reaches the admin without it. Returns `{conn, user}`.
  """
  @spec log_in_as(Plug.Conn.t(), keyword()) :: {Plug.Conn.t(), User.t()}
  def log_in_as(conn, attrs \\ []) do
    attrs =
      case Keyword.fetch(attrs, :permissions) do
        {:ok, permissions} -> Keyword.put(attrs, :permissions, Enum.uniq(["brando.admin.access" | permissions]))
        :error -> attrs
      end

    user = insert_user(attrs)
    {log_in_user(conn, user), user}
  end
end
