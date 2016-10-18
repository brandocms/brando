defmodule <%= application_module %>.DateTimeHelpers do
  import <%= application_module %>.Web.Gettext

  @months %{
    1  => gettext("January"),
    2  => gettext("February"),
    3  => gettext("March"),
    4  => gettext("April"),
    5  => gettext("May"),
    6  => gettext("June"),
    7  => gettext("July"),
    8  => gettext("August"),
    9  => gettext("September"),
    10 => gettext("October"),
    11 => gettext("November"),
    12 => gettext("December"),
  }
  @doc """
  Prettify ecto datetime struct and return date
  """
  def pretty_date(datetime) do
    "#{datetime.day}. #{@months[datetime.month]} #{datetime.year}"
  end

  @doc """
  Prettify ecto datetime struct and return date + time
  """
  def pretty_datetime(datetime) do
    "#{datetime.day}. #{@months[datetime.month]} #{datetime.year} @ #{datetime.hour}:#{datetime.minute}"
  end
end
