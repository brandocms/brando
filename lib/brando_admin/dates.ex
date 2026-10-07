defmodule BrandoAdmin.Dates do
  @moduledoc """
  How the admin shows a date and time: one short and one long form, both in
  `Brando.timezone/0` and the admin's language, with the full timestamp on
  hover.

    * `short/1` — `28.09.26 18:40`, for lists and tight rows
    * `clock/1` — `18:40` today, or the short form, for a recent moment
    * `long/1` — `28. sep. 2026 kl. 18:40` (`28 Sep 2026, 18:40`), where
      there is room
    * `full/1` — the whole timestamp, with seconds, for a title attribute

  `time/1` renders a `<time>` with the machine-readable value and `full/1` as
  its title. Naive datetimes are taken as UTC, as Ecto stores them.
  """
  use Phoenix.Component

  alias Brando.Utils.Datetime

  @doc "`28.09.26 18:40`"
  def short(nil), do: ""
  def short(datetime), do: Datetime.format_datetime(datetime, "%d.%m.%y %H:%M", locale())

  @doc "`18:40` today, the `short/1` form on another day"
  def clock(nil), do: ""

  def clock(datetime) do
    local = local(datetime)
    today = Brando.timezone() |> DateTime.now!() |> DateTime.to_date()

    if DateTime.to_date(local) == today,
      do: Calendar.strftime(local, "%H:%M"),
      else: short(datetime)
  end

  @doc "`28. sep. 2026 kl. 18:40`, or `28 Sep 2026, 18:40` in English"
  def long(nil), do: ""

  def long(datetime) do
    locale = locale()
    local = local(datetime)
    month = month_abbreviation(local.month, locale)

    if locale == "en",
      do: "#{local.day} #{month} #{local.year}, #{Calendar.strftime(local, "%H:%M")}",
      else: "#{local.day}. #{month} #{local.year} kl. #{Calendar.strftime(local, "%H:%M")}"
  end

  @doc "The whole timestamp with seconds, e.g. `28. september 2026 kl. 18:40:12`"
  def full(nil), do: ""

  def full(datetime) do
    if locale() == "en",
      do: Datetime.format_datetime(datetime, "%-d %B %Y, %H:%M:%S", "en"),
      else: Datetime.format_datetime(datetime, "%-d. %B %Y kl. %H:%M:%S", locale())
  end

  attr :at, :any, required: true
  attr :format, :atom, default: :short, values: [:short, :long]
  attr :class, :any, default: nil

  @doc "A `<time>` in the `format` given, with the full timestamp on hover."
  def time(assigns) do
    ~H"""
    <time :if={@at} class={@class} datetime={iso(@at)} title={full(@at)}>{format(@at, @format)}</time>
    """
  end

  defp format(datetime, :short), do: short(datetime)
  defp format(datetime, :long), do: long(datetime)

  defp iso(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime) <> "Z"
  defp iso(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso(%Date{} = date), do: Date.to_iso8601(date)

  defp local(%NaiveDateTime{} = datetime),
    do: datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.shift_zone!(Brando.timezone())

  defp local(%DateTime{} = datetime), do: DateTime.shift_zone!(datetime, Brando.timezone())

  # English "Sep"; Norwegian "sep.", but a month of three letters or fewer
  # ("mai") is written out.
  defp month_abbreviation(month, locale) do
    name = Datetime.get_month_name(month, locale)

    cond do
      locale == "en" -> String.slice(name, 0, 3)
      String.length(name) <= 3 -> name
      true -> String.slice(name, 0, 3) <> "."
    end
  end

  defp locale, do: Gettext.get_locale(Brando.Gettext)
end
