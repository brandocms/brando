defmodule Brando.Utils.StructTest do
  use ExUnit.Case, async: true

  alias Brando.Utils.Struct, as: StructUtils

  defmodule Example do
    defstruct name: nil, count: 0
  end

  test "converts atom and string keys while discarding unknown keys" do
    assert StructUtils.map_to_struct(%{"name" => "Ada", :count => 2, "unknown" => true}, Example) ==
             %Example{name: "Ada", count: 2}
  end

  test "prefers atom keys when both forms are present" do
    assert StructUtils.map_to_struct(%{"name" => "string", name: "atom"}, Example).name == "atom"
  end

  test "builds an empty struct from nil" do
    assert StructUtils.map_to_struct(nil, Example) == %Example{}
  end
end
