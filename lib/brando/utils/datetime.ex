defmodule Brando.Utils.Datetime do
  def format_datetime(datetime, format_string \\ "%d/%m/%y", locale \\ nil)

  def format_datetime(%NaiveDateTime{} = datetime, format_string, locale) do
    locale = locale || Gettext.get_locale()

    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!(Brando.timezone())
    |> Calendar.strftime(
      format_string,
      month_names: fn month ->
        get_month_name(month, locale)
      end,
      day_of_week_names: fn day ->
        get_day_name(day, locale)
      end
    )
  end

  def format_datetime(%DateTime{} = datetime, format_string, locale) do
    locale = locale || Gettext.get_locale()

    datetime
    |> DateTime.shift_zone!(Brando.timezone())
    |> Calendar.strftime(
      format_string,
      month_names: fn month ->
        get_month_name(month, locale)
      end,
      day_of_week_names: fn day ->
        get_day_name(day, locale)
      end
    )
  end

  def get_month_name(month, locale) do
    Gettext.with_locale(locale, fn ->
      Gettext.dgettext(Brando.Gettext, "months", "month_#{month}")
    end)
  end

  def get_day_name(day, locale) do
    Gettext.with_locale(locale, fn ->
      Gettext.dgettext(Brando.Gettext, "days", "day_#{day}")
    end)
  end
end
