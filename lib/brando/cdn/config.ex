defmodule Brando.CDN.Config do
  defstruct enabled: false,
            direct: false,
            media_url: nil,
            bucket: nil,
            s3: %Brando.CDN.S3Config{}
end
