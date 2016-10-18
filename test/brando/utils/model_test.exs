defmodule Brando.Utils.SchemaTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test

  alias Brando.Utils
  alias Brando.Factory

  test "update_field/2" do
    user = Factory.insert(:user)
    assert {:ok, schema} = Utils.Schema.update_field(user, [full_name: "James Bond"])
    assert schema.full_name == "James Bond"
  end
end
