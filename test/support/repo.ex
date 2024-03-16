defmodule BrandoIntegration.Repo do
  use Ecto.Repo,
    otp_app: :brando,
    adapter: Ecto.Adapters.Postgres

  use Brando.SoftDelete.Repo
end
