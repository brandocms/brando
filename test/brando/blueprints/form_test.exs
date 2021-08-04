defmodule Brando.Blueprint.FormTest do
  use ExUnit.Case

  test "form" do
    assert Brando.BlueprintTest.Project.__form__() == []
  end
end
