defmodule Brando.Instagram do
  @moduledoc """
  Brando's interface to Instagram's API.

  To use, first add the Instagram supervisor to your application's
  supervisor in `lib/my_app.ex`:

      supervisor(Brando.Instagram, [MyApp.Instagram]),

  Be sure to also give it a custom name in your_app's `config/brando.exs`.

  ## Options

  These are the options for `config :brando, Brando.Instagram`:

    * `client_id`: Your instagram client id. Find this in the developer section.
    * `interval`: How often we poll for new images
    * `auto_approve`: Set `approved` to `true` on grabbed images.
    * `fetch`: What to fetch.
      * `{:user, "your_name"} - polls for `your_name`'s images.
      * `{:tags, ["tag1", "tag2"]} - polls `tag1` and `tag2`
  """
  use Supervisor
  require Logger

  def start_link(supervisor_name) do
    Supervisor.start_link(__MODULE__, :ok, [name: supervisor_name])
  end

  def init(_) do
    children = [
      worker(Brando.Instagram.Server, [Brando.Instagram.config(:server_name)])
    ]
    supervise(children, strategy: :one_for_one)
  end
  @doc """
  Grab `key` from config
  """
  def config(key) do
    cfg = Application.get_env(:brando, Brando.Instagram)
    Keyword.get(cfg, key)
  end
end
