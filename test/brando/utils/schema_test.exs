defmodule Brando.Utils.SchemaTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test

  alias Brando.Factory
  alias Brando.Utils

  test "update_field/2" do
    user = Factory.insert(:random_user)
    assert {:ok, schema} = Utils.Schema.update_field(user, full_name: "James Bond")
    assert schema.full_name == "James Bond"
  end
end
