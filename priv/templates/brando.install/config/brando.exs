# The Brando.Images defaults `mix brando.install` adds to an application's
# config/brando.exs, key by key, leaving keys the application already sets.
# The installer reads only this block.

import Config

config :brando, Brando.Images,
  processor_module: Brando.Images.Processor.Vix,
  default_config: %{
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif", "image/avif", "image/webp", "image/svg+xml"],
    upload_path: Path.join(["images", "site", "default"]),
    default_size: :xlarge,
    random_filename: true,
    size_limit: 10_240_000,
    # micro, thumb, small, medium, large and xlarge; see `Brando.Images.Size`
    sizes: :standard,
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
