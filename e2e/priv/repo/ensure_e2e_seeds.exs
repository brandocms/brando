alias Brando.Users.User
alias E2eProject.Repo

case Repo.get_by(User, email: "admin@brandocms.com") do
  nil ->
    IO.puts("Seeding fresh E2E database...")
    # The seed content lives in `public`, also with several sites, where the
    # tests copy it into each site's schema
    Brando.Tenant.with_public(fn -> Code.eval_file(Path.join(__DIR__, "e2e_seeds.exs")) end)

  %User{} ->
    :ok
end
