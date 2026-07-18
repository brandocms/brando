defmodule Brando.CDN.Config do
  @moduledoc false
  defstruct enabled: false,
            direct: false,
            direct_acl: nil,
            media_url: nil,
            bucket: nil,
            keep_local_copy: true,
            s3: %Brando.CDN.S3Config{}
end
