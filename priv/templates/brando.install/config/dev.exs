import Config

config :<%= application_name %>, show_breakpoint_debug: true

# Configure your database
config :<%= application_name %>, <%= application_module %>.Repo,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  stacktrace: true

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :<%= application_name %>, <%= application_module %>Web.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false

# Watch static and templates for browser reloading.
config :<%= application_name %>, <%= application_module %>Web.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(png|jpeg|jpg|gif|svg)$",
      ~r"priv/static/css/.*(css)$",
      ~r"priv/static/js/admin/.*(js)$",
      ~r"priv/static/css/admin/.*(css)$",
      ~r"priv/gettext/(backend|frontend)/.*(po)$",
      ~r"lib/<%= application_name %>_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"
config :logger, truncate: :infinity
config :logger, :console, truncate: :infinity

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 60

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
