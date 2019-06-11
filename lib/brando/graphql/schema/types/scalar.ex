defmodule Brando.Schema.Types.Scalar do
  use Brando.Web, :absinthe
  alias Absinthe.Blueprint

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

  @desc """
  Represents an uploaded file or image.
  """
  scalar :upload_or_image do
    parse fn
      %Blueprint.Input.String{value: value}, context ->
        # if ctx :uploads is empty, it's an image.
        case Map.fetch(context[:__absinthe_plug__][:uploads] || %{}, value) do
          :error ->
            # it's an image/focal update
            {:ok, img_params} = Jason.decode(value)
            {:ok, %Brando.Type.Focal{focal: img_params["focal"]}}

          {:ok, upload} ->
            {:ok, upload}
        end

      %Blueprint.Input.Null{}, _ ->
        {:ok, nil}

      _, _ ->
        :error
    end

    serialize fn _ ->
      raise "The `:upload` scalar cannot be returned!"
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

  defp encode(value), do: value
end
