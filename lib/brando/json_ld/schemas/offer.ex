defmodule Brando.JSONLD.Schema.Offer do
  @moduledoc """
  An offer to sell a product: what it costs, in which currency, and whether
  it can be bought now.

  Google requires `price` and `priceCurrency` (ISO 4217, such as `"NOK"`), and
  recommends `availability`. Build it from a map or an entry:

      Offer.build(%{price: 249, price_currency: "NOK", availability: :in_stock, url: "https://…"})

  `availability` takes a schema.org item availability as an atom or string,
  in snake case (`:in_stock`, `"pre_order"`), as its name (`"InStock"`) or as
  its URL; it is emitted as the URL Google expects.
  """

  @derive Jason.Encoder
  defstruct "@type": "Offer",
            price: nil,
            priceCurrency: nil,
            availability: nil,
            priceValidUntil: nil,
            url: nil

  @availabilities ~w(BackOrder Discontinued InStock InStoreOnly LimitedAvailability MadeToOrder
                     OnlineOnly OutOfStock PreOrder PreSale Reserved SoldOut)

  @doc "The schema.org item availabilities, by name."
  @spec availabilities() :: [String.t()]
  def availabilities, do: @availabilities

  @spec build(map() | nil) :: %__MODULE__{} | nil
  def build(nil), do: nil

  def build(data) when is_map(data) do
    %__MODULE__{
      price: data |> get([:price]) |> price(),
      priceCurrency: get(data, [:price_currency, :currency, :priceCurrency]),
      availability: data |> get([:availability]) |> availability(),
      priceValidUntil: data |> get([:price_valid_until, :priceValidUntil]) |> date(),
      url: get(data, [:url])
    }
  end

  @doc """
  The schema.org URL for an availability, or `nil` when it isn't one.

      iex> Brando.JSONLD.Schema.Offer.availability(:in_stock)
      "https://schema.org/InStock"
  """
  @spec availability(term()) :: String.t() | nil
  def availability(nil), do: nil
  def availability(value) when is_atom(value), do: value |> Atom.to_string() |> availability()

  def availability(value) when is_binary(value) do
    name =
      value
      |> String.replace_prefix("https://schema.org/", "")
      |> String.replace_prefix("http://schema.org/", "")
      |> Macro.camelize()

    if name in @availabilities, do: "https://schema.org/" <> name
  end

  def availability(_value), do: nil

  defp price(%Decimal{} = price), do: Decimal.to_string(price, :normal)
  defp price(price), do: price

  defp date(%Date{} = date), do: Date.to_iso8601(date)
  defp date(%DateTime{} = datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()
  defp date(%NaiveDateTime{} = datetime), do: datetime |> NaiveDateTime.to_date() |> Date.to_iso8601()
  defp date(value), do: value

  defp get(data, keys), do: Enum.find_value(keys, &Map.get(data, &1))
end
