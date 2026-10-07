defmodule Brando.JSONLD.Schema.MonetaryAmount do
  @moduledoc """
  A salary, for a job posting's `baseSalary`: a currency, an amount or a
  range, and the period it is paid for.

      MonetaryAmount.build(%{currency: "NOK", value: 650_000, unit: "YEAR"})
      MonetaryAmount.build(%{currency: "NOK", min: 50_000, max: 60_000, unit: "MONTH"})

  `unit` is one of `HOUR`, `DAY`, `WEEK`, `MONTH` or `YEAR`.
  """

  @derive Jason.Encoder
  defstruct "@type": "MonetaryAmount",
            currency: nil,
            value: nil

  @spec build(map() | nil) :: %__MODULE__{} | nil
  def build(nil), do: nil

  def build(data) when is_map(data) do
    %__MODULE__{
      currency: Map.get(data, :currency),
      value: %{
        "@type": "QuantitativeValue",
        value: data |> Map.get(:value) |> number(),
        minValue: data |> Map.get(:min) |> number(),
        maxValue: data |> Map.get(:max) |> number(),
        unitText: data |> Map.get(:unit) |> unit()
      }
    }
  end

  defp number(%Decimal{} = value), do: Decimal.to_float(value)
  defp number(value), do: value

  defp unit(nil), do: nil
  defp unit(unit), do: unit |> to_string() |> String.upcase()
end
