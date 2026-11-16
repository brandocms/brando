defmodule Brando.Test.SSGEndpoint do
  @moduledoc """
  A Phoenix endpoint for static build tests, running as a server whose HTTP
  listener is a `Brando.WebhookReceiver`: Brando's test dependencies have no
  HTTP server for Phoenix. Its adapter reports the receiver's address as the
  endpoint's listener (`server_info/1`), and the receiver answers the build's
  requests.

      receiver = Brando.Test.SSGEndpoint.start(fn _request -> {200, "page"} end)

  `start/2` starts the endpoint under the test's supervisor, so it stops with
  the test. Pass `listen_ip:` for the address the listener says it is bound
  to (default `{0, 0, 0, 0}`, a wildcard), `receiver_ip:` for the loopback
  address the receiver really listens on (default `{127, 0, 0, 1}`) and
  `config:` for more of the endpoint's configuration.
  """

  use Phoenix.Endpoint, otp_app: :brando

  @doc "Starts the endpoint, listening where a new `Brando.WebhookReceiver` answers with `respond`."
  def start(respond, opts \\ []) do
    receiver = Brando.WebhookReceiver.start(respond, Keyword.get(opts, :receiver_ip, {127, 0, 0, 1}))
    listen_ip = Keyword.get(opts, :listen_ip, {0, 0, 0, 0})

    config =
      Keyword.merge(
        [
          adapter: __MODULE__.Adapter,
          http: [ip: listen_ip, port: receiver.port],
          server: true,
          secret_key_base: String.duplicate("ssg-endpoint", 6)
        ],
        Keyword.get(opts, :config, [])
      )

    previous = Application.fetch_env(:brando, __MODULE__)
    Application.put_env(:brando, __MODULE__, config)

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:brando, __MODULE__, value)
        :error -> Application.delete_env(:brando, __MODULE__)
      end
    end)

    ExUnit.Callbacks.start_supervised!(__MODULE__)
    receiver
  end

  defmodule Adapter do
    @moduledoc false
    # A listener started elsewhere (the receiver): nothing to supervise here.
    def child_specs(_endpoint, _config), do: []

    def server_info(endpoint, scheme) do
      case endpoint.config(scheme) do
        options when is_list(options) -> {:ok, {Keyword.fetch!(options, :ip), Keyword.fetch!(options, :port)}}
        nil -> {:error, :no_listener}
      end
    end
  end
end
