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
      {:ok, Enum.map(p.fields, &(&1.input_value.normalized.value))}
    end
  end

  scalar :json, name: "JSON" do
    parse &Poison.decode(&1.value)
    serialize &Poison.encode!/1
  end
end
