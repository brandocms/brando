defmodule Brando.Utils.ModelTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  
  alias Brando.Utils
  alias Brando.Factory

  test "update_field/2" do
    user = Factory.insert(:user)
    assert {:ok, model} = Utils.Model.update_field(user, [full_name: "James Bond"])
    assert model.full_name == "James Bond"
  end
end
