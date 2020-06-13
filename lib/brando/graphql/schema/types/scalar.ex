defmodule Brando.Schema.Types.Scalar do
  use Brando.Web, :absinthe

  scalar :time, description: "ISOz time" do
    parse &Timex.parse(&1.value, "{ISO:Extended:Z}")
    serialize &Timex.format!(&1, "{ISO:Extended:Z}")
  end

  scalar :date, description: "ISOz time" do
    parse &Timex.parse(&1.value, "%Y-%m-%d", :strftime)
    serialize &Timex.format!(&1, "%Y-%m-%d", :strftime)
  end

  scalar :list, description: "JS array to list instead of map" do
    parse fn p ->
      {:ok, Enum.map(p.fields, & &1.input_value.normalized.value)}
    end
  end

  scalar :order, description: "Order string: field dir, field dir, field dir" do
    parse fn
      %{value: string} ->
        order_tuples =
          string
          |> String.split(",")
          |> Enum.map(fn e ->
            String.trim(e)
            |> String.split(" ")
            |> Enum.map(&String.to_atom/1)
            |> List.to_tuple()
          end)

        {:ok, order_tuples}
    end
  end

  scalar :atom, description: "Atom" do
    parse fn
      %{value: p} when is_binary(p) -> {:ok, String.to_existing_atom(p)}
      %{value: p} when is_atom(p) -> {:ok, p}
    end

    serialize fn
      p when is_binary(p) -> {:ok, String.to_existing_atom(p)}
      p when is_atom(p) -> {:ok, p}
    end
  end

  scalar :json, name: "Json" do
    description("""
    The `Json` scalar type represents arbitrary json string data, represented as UTF-8
    character sequences. The Json type is most often used to represent a free-form
    human-readable json string.
    """)

    serialize(&encode/1)
    parse(&decode/1)
  end

  @spec decode(Absinthe.Blueprint.Input.String.t()) :: {:ok, term()} | :error
  @spec decode(Absinthe.Blueprint.Input.Null.t()) :: {:ok, nil}
  defp decode(%Absinthe.Blueprint.Input.String{value: value}) do
    case Jason.decode(value) do
      {:ok, result} -> {:ok, result}
      _ -> :error
    end
  end

  defp decode(%Absinthe.Blueprint.Input.Null{}) do
    {:ok, nil}
  end

  defp decode(_) do
    :error
  end

  defp encode(value) do
    value
  end
end
