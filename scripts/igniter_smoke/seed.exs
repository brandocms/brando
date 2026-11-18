alias Brando.Users.User
alias IgniterSmoke.Repo

user =
  Repo.insert!(%User{
    name: "Installer Smoke",
    email: "installer@example.test",
    password: Bcrypt.hash_pwd_salt("installer-smoke-test"),
    role: :superuser,
    language: :en
  })

{:ok, user} = Brando.Users.update_user(user.id, %{config: %{reset_password_on_first_login: false}}, user)

# Every delete and restore goes through the application's Repo, which
# mix brando.install gives Brando's soft-delete functions
scratch =
  Repo.insert!(%User{
    name: "Soft delete smoke",
    email: "soft-delete@example.test",
    password: Bcrypt.hash_pwd_salt("soft-delete-smoke-test"),
    role: :user,
    language: :en
  })

{:ok, %User{deleted_at: %DateTime{}} = deleted} = Brando.Repo.soft_delete(scratch)
{:ok, %User{deleted_at: nil} = restored} = Brando.Repo.restore(deleted)
Repo.delete!(restored)

case Brando.Tenant.mode() do
  :none ->
    Brando.Sites.create_default_identity("en")
    Brando.Sites.create_default_seo("en")

  mode when mode in [:single, :multi] ->
    {:ok, site} =
      Brando.Tenant.Setup.create_site(
        %{
          name: "Installer Smoke",
          key: "smoke",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        },
        user
      )

    environment = Brando.Tenant.Cache.get_live_env(site.key)

    environment
    |> Ecto.Changeset.change(domain: "127.0.0.1")
    |> Repo.update!()
end

IO.puts("Disposable account and selected tenancy initialized")
