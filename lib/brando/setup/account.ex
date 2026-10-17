defmodule Brando.Setup.Account do
  @moduledoc """
  Account creation for setup tasks.

  Used by `mix brando.gen.admin` and `mix brando.setup`. Passwords are hashed
  here; no validation rules are applied beyond the schema's, since the first
  account is created before any account exists to authorize the change.
  """

  import Ecto.Query

  alias Brando.Users.User
  alias Brando.Users.UserConfig

  @doc """
  Inserts a superuser account.

  Expects `:email`, `:name` and `:password`. The password is hashed before
  insertion. Raises on a duplicate email, matching the rest of the setup tasks.

  Whoever runs the setup task chose the password, so the account is not asked
  to change it on first login (`reset_password_on_first_login`).
  """
  @spec create_superuser(map()) :: User.t()
  def create_superuser(%{email: email, name: name, password: password}) do
    Brando.Repo.insert!(%User{
      name: name,
      email: email,
      password: Bcrypt.hash_pwd_salt(password),
      avatar: nil,
      role: :superuser,
      language: default_admin_language(),
      config: %UserConfig{reset_password_on_first_login: false}
    })
  end

  @doc "Returns the oldest active superuser, or `nil`."
  @spec superuser() :: User.t() | nil
  def superuser do
    Brando.Repo.one(
      from u in User,
        where: u.role == :superuser and u.active == true and is_nil(u.deleted_at),
        order_by: [asc: u.id],
        limit: 1
    )
  end

  defp default_admin_language do
    case Brando.config(:default_admin_language) do
      language when is_binary(language) -> String.to_existing_atom(language)
      language when is_atom(language) and not is_nil(language) -> language
      _ -> :en
    end
  end
end
