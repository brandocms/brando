defmodule Brando.CDN.S3Config do
  @moduledoc false
  defstruct access_key_id: nil,
            secret_access_key: nil,
            scheme: "https://",
            host: "ams3.digitaloceanspaces.com",
            region: "ams3"
end
