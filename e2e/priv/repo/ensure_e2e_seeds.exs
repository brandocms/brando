alias Brando.Users.User
alias E2eProject.Repo

case Repo.get_by(User, email: "admin@brandocms.com") do
  nil ->
    IO.puts("Seeding fresh E2E database...")
    Code.eval_file(Path.join(__DIR__, "e2e_seeds.exs"))

  %User{} ->
    :ok
end
