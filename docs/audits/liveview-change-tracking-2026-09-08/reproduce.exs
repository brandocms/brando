# Phoenix engine semantics probes. Application regressions now live under test/brando_admin.
Application.load(:phoenix_live_view)
unless Application.spec(:phoenix_live_view, :vsn) == ~c"1.2.11", do: raise("wrong LiveView version")
ExUnit.start()

defmodule TrackingProbe do
  use Phoenix.Component

  def spread(assigns), do: ~H"<.child {assigns} />"
  def explicit(assigns), do: ~H"<.child value={@value} />"
  def direct(assigns), do: ~H"{child(assigns)}"
  def child(assigns), do: ~H"<p>{@value}</p>"

  def bad_derived(assigns) do
    assigns = Map.put(assigns, :doubled, assigns.value * 2)
    ~H"<p>{@doubled}</p>"
  end

  def good_derived(assigns) do
    assigns = assign(assigns, :doubled, assigns.value * 2)
    ~H"<p>{@doubled}</p>"
  end

  def constant(assigns), do: ~H"<p>{Process.get(:audit_constant)}</p>"
end

defmodule LiveViewAuditTest do
  use ExUnit.Case

  test "spread disables child tracking, explicit props skip unrelated changes, direct call preserves child tracking" do
    assigns = %{__changed__: %{other: true}, value: "stable", other: 2}
    [spread] = TrackingProbe.spread(assigns).dynamic.(true)
    assert spread.dynamic.(true) == ["stable"]
    assert TrackingProbe.explicit(assigns).dynamic.(true) == [nil]
    [direct] = TrackingProbe.direct(assigns).dynamic.(true)
    assert direct.dynamic.(true) == [nil]
  end

  test "generic assign mutation loses the new derived key" do
    assigns = %{__changed__: %{value: true}, value: 2}
    assert TrackingProbe.bad_derived(assigns).dynamic.(true) == [nil]
    assert TrackingProbe.good_derived(assigns).dynamic.(true) == ["4"]
  end

  test "a zero-assign expression is skipped during tracked updates" do
    Process.put(:audit_constant, "constant")
    assert TrackingProbe.constant(%{__changed__: nil}).dynamic.(false) == ["constant"]
    assert TrackingProbe.constant(%{__changed__: %{other: true}}).dynamic.(true) == [nil]
  end

  test "nil LiveComponent IDs raise" do
    assert_raise ArgumentError, ~r/got: nil/, fn ->
      Phoenix.Component.live_component(%{module: __MODULE__, id: nil})
    end
  end

end
