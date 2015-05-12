defmodule Brando.Instagram do
  @moduledoc """
  Brando's interface to Instagram's API.

  To use, first add the Instagram server worker to your application's
  supervisor in `lib/my_app.ex`:

      worker(Brando.Instagram.Server, [Brando.Instagram.cfg(:server_name)])

  Be sure to give it a custom name in your_app's `config/brando.exs`.

  ## Options

  These are the options for `config :brando, Brando.Instagram`:

    * `client_id`: Your instagram client id. Find this in the developer section.
    * `interval`: How often we poll for new images
    * `auto_approve`: Set `approved` to `true` on grabbed images.
    * `fetch`: What to fetch.
      * `{:user, "your_name"} - polls for `your_name`'s images.
      * `{:tags, ["tag1", "tag2"]} - polls `tag1` and `tag2`
  """

  @doc """
  Grab `key` from config
  """
  def cfg(key) do
    Application.get_env(:brando, Brando.Instagram) |> Keyword.get(key)
  end
end