defmodule <%= app_module %>.Repo do
  use Ecto.Repo,
    otp_app: :<%= app_name %>,
    adapter: Ecto.Adapters.Postgres

  use Brando.SoftDelete.Repo
end
