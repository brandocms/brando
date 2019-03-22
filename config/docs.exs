use Mix.Config

# Configure Guardian for auth.
config :guardian, Guardian,
  # optional
  allowed_algos: ["HS512"],
  # optional
  verify_module: Guardian.JWT,
  issuer: "BrandoTesting",
  ttl: {30, :days},
  # optional
  verify_issuer: true,
  secret_key: "XX9ND0BmT51mrKWp46WdYZoPWOv6awnEScbNg3HPWTnnl605tmDKEogZCb9109gb",
  serializer: Brando.GuardianSerializer
