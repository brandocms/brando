defmodule Brando.Sites.SEOBaseURLWarningTest do
  use ExUnit.Case, async: true

  alias Brando.Sites.SEO

  defp form(params), do: %SEO{} |> Ecto.Changeset.cast(params, [:base_url]) |> Phoenix.Component.to_form()

  test "warns while the base URL is empty" do
    assert SEO.base_url_missing?(form(%{}))
    assert SEO.base_url_missing?(form(%{"base_url" => ""}))
    refute SEO.base_url_missing?(form(%{"base_url" => "https://example.com"}))
  end
end
