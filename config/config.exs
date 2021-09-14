# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :brando, ecto_repos: [BrandoIntegration.Repo]

config :brando,
  languages: [
    [value: "en", text: "English"],
    [value: "no", text: "Norsk"]
  ]

config :brando, Brando.Images,
  processor_module: Brando.Images.Processor.Sharp,
  default_config: %{
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    upload_path: Path.join(["images", "site", "default"]),
    default_size: :xlarge,
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "150x150>", "quality" => 75, "crop" => true},
      "small" => %{"size" => "700", "quality" => 75},
      "medium" => %{"size" => "1100", "quality" => 75},
      "large" => %{"size" => "1700", "quality" => 75},
      "xlarge" => %{"size" => "2100", "quality" => 75}
    },
    srcset: %{
      default: [
        {"small", "700w"},
        {"medium", "1100w"},
        {"large", "1700w"},
        {"xlarge", "2100w"}
      ]
    }
  },
  default_srcset: %{
    default: [
      {"small", "700w"},
      {"medium", "1100w"},
      {"large", "1700w"},
      {"xlarge", "2100w"}
    ]
  }

config :phoenix, :json_library, Jason

# These are defaults for internals, mostly overridden for testing
# purposes. We put them here to not pollute the brando.exs file.
config :brando,
  auth_sleep_duration: 2_000,
  otp_app: :brando

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
