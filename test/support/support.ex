defmodule Brando.Test.Support do
  @moduledoc false
  import ExUnit.Assertions

  def assert_attr(target, attr, value) do
    assert Floki.attribute(target, attr) == value
    target
  end
end
