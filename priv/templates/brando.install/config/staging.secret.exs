use Mix.Config

# In this file, we keep production configuration that
# you'll likely want to automate and keep away from
# your version control system.
#
# You should document the content of this
# file or create a script for recreating it, since it's
# kept out of version control and might be hard to recover
# or recreate for your teammates (or yourself later on).
config :<%= application_name %>, <%= application_module %>Web.Endpoint,
  secret_key_base: "<%= :crypto.strong_rand_bytes(64) |> Base.encode64 |> binary_part(0, 64)%>"

# Configure your database
config :<%= application_name %>, <%= application_module %>.Repo,
  username: "<%= application_name %>",
  password: "staging_pass",
  database: "<%= application_name %>_staging",
  socket_options: [recbuf: 8192, sndbuf: 8192],
  pool_size: 5
