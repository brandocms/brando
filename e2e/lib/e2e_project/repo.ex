defmodule E2eProject.Repo do
  use Ecto.Repo,
    otp_app: :e2e_project,
    adapter: Ecto.Adapters.Postgres

  use Brando.SoftDelete.Repo
end
