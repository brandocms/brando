use Mix.Config

config :<%= application_name %>, <%= application_module %>Web.Endpoint,
  secret_key_base: "<%= :crypto.strong_rand_bytes(64) |> Base.encode64 |> binary_part(0, 64)%>"

config :<%= application_name %>, <%= application_module %>.Repo,
  # ssl: true,
  url: "postgres://<%= application_name %>:PROD_PASSWORD_HERE@localhost/<%= application_name %>_prod",
  socket_options: [recbuf: 8192, sndbuf: 8192],
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "15")
