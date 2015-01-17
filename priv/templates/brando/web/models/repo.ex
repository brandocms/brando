defmodule <%= application_name %>.Repo do
  use Ecto.Repo,
    otp_app: <%= application_atom %>,
    adapter: Ecto.Adapters.Postgres
end