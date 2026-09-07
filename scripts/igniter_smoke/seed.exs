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
