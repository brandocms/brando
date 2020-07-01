defmodule <%= application_module %>.Repo do
  use Ecto.Repo,
    otp_app: :<%= application_name %>,
    adapter: Ecto.Adapters.Postgres

  use Brando.SoftDelete.Repo
end
