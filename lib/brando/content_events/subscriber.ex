defmodule Brando.ContentEvents.Subscriber do
  @moduledoc """
  A module that receives every content event. List it in
  `config :brando, Brando.ContentEvents, subscribers: [...]`; see
  `Brando.ContentEvents` for an example.

  `handle_event/1` runs inside the dispatcher job, in the event's site and
  environment, one subscriber after the other. Keep it short: queue your own
  job for anything slow, such as an HTTP request. Return `{:error, reason}`
  (or raise) to have the event dispatched again later; anything else counts
  as handled. A retry reaches every subscriber again, so handle an
  `event.id` you have already seen as a no-op.
  """

  @callback handle_event(Brando.ContentEvents.Event.t()) :: :ok | {:error, term()} | any()
end
