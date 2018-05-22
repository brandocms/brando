defmodule Brando.Schema.Types.Files do
  use Brando.Web, :absinthe

  object :file_type do
    field :mimetype, :string
    field :path, :string
    field :size, :string

    field :url, :string do
      resolve fn file, _, _ ->
        {:ok, Brando.Utils.media_url(file.path)}
      end
    end
  end
end
