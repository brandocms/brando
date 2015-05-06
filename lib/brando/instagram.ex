defmodule Brando.Instagram do
  @moduledoc """
  Brando's interface to Instagram's API.

  To use, first add the Instagram server worker to your application's
  supervisor in `lib/my_app.ex`:

      worker(Brando.Instagram.Server, [:myapp_instagram])

  Give it a custom name (`:myapp_instagram`) so there are no clashes.

  The setup is found in your application's `config/brando.exs`.

  `client_id`: Your instagram client id. Find this in the developer section.
  `interval`: How often we poll for new images
  `auto_approve`: Set `approved` to `true` on grabbed images.
  `fetch`: What to fetch.
    * `{:user, "your_name"}
    * `{:tags, ["tag1", "tag2"]}
  """

  @doc """
  Grab `key` from config
  """
  def cfg(key) do
    Application.get_env(:brando, Brando.Instagram) |> Keyword.get(key)
  end
end