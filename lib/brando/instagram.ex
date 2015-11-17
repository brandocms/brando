defmodule Brando.Instagram do
  @moduledoc """
  Brando's interface to Instagram's API.

  To use, first add as a worker to your application's
  supervision tree in `lib/my_app.ex`:

      worker(Brando.Instagram, []),

  ## Configuration options

  These are the options for `config :brando, Brando.Instagram`:

    * `client_id`: Your instagram client id. Find this in the developer section.
    * `interval`: How often we poll for new images
    * `auto_approve`: Set `approved` to `true` on grabbed images.
    * `fetch`: What to fetch.
      * `{:user, "your_name"} - polls for `your_name`'s images.
      * `{:tags, ["tag1", "tag2"]} - polls `tag1` and `tag2`
  """

  @doc false
  def start_link do
    import Supervisor.Spec, warn: false

    children = [
      worker(Brando.Instagram.Server, [])
    ]

    opts = [strategy: :one_for_one, name: Brando.Instagram.Supervisor]
    {:ok, _pid} =  Supervisor.start_link(children, opts)
  end

  @doc """
  Grab `key` from config
  """
  def config(key) do
    cfg = Application.get_env(:brando, Brando.Instagram)
    Keyword.get(cfg, key)
  end
end
