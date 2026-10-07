defmodule BrandoAdmin.DatesTest do
  # One way to show a date in the admin: local time, the admin's language.
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias BrandoAdmin.Dates

  # 16:40 UTC is 18:40 in Oslo in September (CEST)
  @at ~U[2026-09-28 16:40:12Z]

  setup do
    previous = Gettext.get_locale(Brando.Gettext)
    on_exit(fn -> Gettext.put_locale(Brando.Gettext, previous) end)
    :ok
  end

  test "short and long, in local time" do
    Gettext.put_locale(Brando.Gettext, "no")
    assert Dates.short(@at) == "28.09.26 18:40"
    assert Dates.long(@at) == "28. sep. 2026 kl. 18:40"
    assert Dates.full(@at) == "28. september 2026 kl. 18:40:12"
  end

  test "English months, and a short Norwegian month written out" do
    Gettext.put_locale(Brando.Gettext, "en")
    assert Dates.long(@at) == "28 Sep 2026, 18:40"

    Gettext.put_locale(Brando.Gettext, "no")
    assert Dates.long(~U[2026-05-04 10:00:00Z]) == "4. mai 2026 kl. 12:00"
  end

  test "naive datetimes are UTC" do
    Gettext.put_locale(Brando.Gettext, "no")
    assert Dates.short(~N[2026-09-28 16:40:12]) == "28.09.26 18:40"
    assert Dates.short(nil) == ""
  end

  test "clock/1 is the time today, and the short form on another day" do
    Gettext.put_locale(Brando.Gettext, "no")
    now = DateTime.utc_now()
    local = DateTime.shift_zone!(now, Brando.timezone())

    assert Dates.clock(now) == Calendar.strftime(local, "%H:%M")
    assert Dates.clock(@at) == "28.09.26 18:40"
    assert Dates.clock(nil) == ""
  end

  test "time/1 carries the machine value and the full timestamp" do
    Gettext.put_locale(Brando.Gettext, "no")
    html = rendered_to_string(Dates.time(%{at: @at, format: :long, class: nil, __changed__: nil}))

    assert html =~ ~s(datetime="2026-09-28T16:40:12Z")
    assert html =~ ~s(title="28. september 2026 kl. 18:40:12")
    assert html =~ "28. sep. 2026 kl. 18:40"
  end
end
