defmodule Brando.Blueprint.ListingFiltersTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Listings
  alias Brando.Blueprint.Listings.Filter

  defp toggle(opts \\ []), do: struct(Filter, [label: "Featured", key: "featured", type: :boolean] ++ opts)

  test "a toggle switched off stops applying, unless it is told off means false" do
    # off: :all — untouched and off are the same: no filter.
    assert Listings.resting_value(toggle()) == nil
    assert Listings.off_value(toggle()) == ""

    # off: false — the filter rests at false and switches back to it.
    assert Listings.resting_value(toggle(off: false)) == "false"
    assert Listings.off_value(toggle(off: false)) == "false"

    # default: true — it rests on, and off overrides the default.
    assert Listings.resting_value(toggle(default: true)) == "true"
    assert Listings.off_value(toggle(default: true)) == "off"
    assert Listings.off_value(toggle(default: true, off: false)) == "false"
  end

  test "defaults put each filter where it rests, and an overridden default is dropped" do
    listing = %{filters: [toggle(key: "a"), toggle(key: "b", off: false), toggle(key: "c", default: true)]}

    assert Listings.merge_filter_defaults(%{}, listing) == %{filter: %{b: "false", c: "true"}}

    switched_off = %{filter: %{b: "false", c: "off"}}
    assert Listings.drop_switched_off(switched_off, listing) == %{filter: %{b: "false"}}
  end
end
