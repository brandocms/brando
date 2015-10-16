defmodule Brando.Utils.ModelTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  alias Brando.Utils
  alias Brando.User

  @params %{"avatar" => nil, "role" => ["2", "4"], "language" => "nb",
            "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
            "password" => "finimeze", "status" => "1",
            "submit" => "Submit", "username" => "zabuzasixu"}

  test "update_field/2" do
    assert {:ok, user}
           = User.create(@params)
    assert {:ok, model}
           = Utils.Model.update_field(user, [full_name: "James Bond"])
    assert model.full_name
           == "James Bond"
  end
end
