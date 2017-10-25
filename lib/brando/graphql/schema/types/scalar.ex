defmodule Brando.Schema.Types.Scalar do
  use Brando.Web, :absinthe
  alias Brando.Schema

  scalar :time, description: "ISOz time" do
    parse &Timex.parse(&1.value, "{ISO:Extended:Z}")
    serialize &Timex.format!(&1, "{ISO:Extended:Z}")
  end

  scalar :date, description: "ISOz time" do
    parse &Timex.parse(&1.value, "%Y-%m-%d", :strftime)
    serialize &Timex.format!(&1, "%Y-%m-%d", :strftime)
  end
end
