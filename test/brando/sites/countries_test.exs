defmodule Brando.Sites.CountriesTest do
  use ExUnit.Case, async: true

  alias Brando.Sites.Countries

  defp form(country), do: Phoenix.Component.to_form(%{"country" => country})

  test "labels follow the admin locale and values are ISO codes" do
    Gettext.put_locale("no")
    options = Countries.options(form("NO"), [])
    assert %{value: "NO", label: "Norge"} in options
    assert List.last(options) == %{value: "AX", label: "Åland"}

    Gettext.put_locale("en")
    assert %{value: "NO", label: "Norway"} in Countries.options(form("NO"), [])
  end

  test "keeps a free-text value typed before the field was a select" do
    Gettext.put_locale("en")
    assert [%{value: "Norge", label: "Norge"} | _] = Countries.options(form("Norge"), [])
    assert [%{value: "AF"} | _] = Countries.options(form(""), [])
  end
end
