defmodule Mix.Brando.Igniter.NodeRangeTest do
  use ExUnit.Case, async: true

  alias Mix.Brando.Igniter.NodeRange

  test "tells whether a range allows a Node major" do
    for range <-
          ["", "*", "22", "22.x", "v22", ">=18", ">= 18.0.0", "^22.1.0", "~22.12", "18 || 20 || 22", ">=18 <23"] ++
            ["16 - 22", "<=22", ">21", "22.11.0", "^18 || ^20 || ^22", ">=20.19 <21 || >=22.12", "22.0.0-rc.1"] do
      assert NodeRange.allows_major?(range, 22) == {:ok, true}, range
    end

    for range <- ["16", "16.x", "^16.20.0", "~16", ">=14 <17", "<22", ">22", "16 - 21", "<=21.9", ">=23", "18 || 20"] do
      assert NodeRange.allows_major?(range, 22) == {:ok, false}, range
    end
  end

  test "is :error for what it cannot read" do
    for range <- ["lts/*", "node", ">=22 <foo", "22.1.2.3", "16 - 18 - 22"] do
      assert NodeRange.allows_major?(range, 22) == :error, range
    end
  end
end
