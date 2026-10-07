defmodule Brando.ContentEvents.Subscriber do
  @moduledoc """
  A module that receives every content event. List it in
  `config :brando, Brando.ContentEvents, subscribers: [...]`; see
  `Brando.ContentEvents` for an example.

  `handle_event/1` runs inside the dispatcher job, in the event's site and
  environment, one subscriber after the other. Keep it short: queue your own
  job for anything slow, such as an HTTP request. The return value is
  ignored, and an exception is logged without affecting other subscribers.
  """

  @callback handle_event(Brando.ContentEvents.Event.t()) :: any()
end
