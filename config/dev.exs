use Mix.Config

config :logger, :console, format: "[$level] $message\n"
config :logger, :level, :debug

# Configure Guardian for auth.
config :guardian, Guardian,
  allowed_algos: ["HS512"], # optional
  verify_module: Guardian.JWT,  # optional
  issuer: "BrandoTesting",
  ttl: {30, :days},
  verify_issuer: true, # optional
  secret_key: "XX9ND0BmT51mrKWp46WdYZoPWOv6awnEScbNg3HPWTnnl605tmDKEogZCb9109gb",
  serializer: Brando.GuardianSerializer
