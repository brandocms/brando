defmodule Brando.JSONLD.Schema.EventTest do
  use ExUnit.Case, async: true

  alias Brando.JSONLD.Schema.Event

  test "an event carries the name and url schema.org requires" do
    json =
      Event
      |> struct!(name: "Opening night", url: "https://example.com/events/opening", startDate: "2026-10-03")
      |> Jason.encode!()
      |> Jason.decode!()

    assert json["@type"] == "Event"
    assert json["name"] == "Opening night"
    assert json["url"] == "https://example.com/events/opening"
    assert json["startDate"] == "2026-10-03"
  end
end
