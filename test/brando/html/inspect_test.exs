defmodule Brando.HTML.InspectTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  import Brando.HTML.Inspect
  alias Brando.Users.Model.User

  @params %{"avatar" => nil, "role" => ["2", "4"],
            "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
            "password" => "finimeze", "status" => "1",
            "submit" => "Submit", "username" => "zabuzasixu"}

  test "model/1" do
    assert {:ok, user} = User.create(@params)
    {:safe, ret} = model(user)
    assert ret =~ "zabuzasixu"
    assert ret =~ "** sensurert **"
    assert ret =~ "Nita Bond"
  end

  test "model_str/1" do
    assert {:ok, user} = User.create(@params)
    assert model_str(user) == "Nita Bond (zabuzasixu)"
  end

  test "model_name/2" do
    assert {:ok, user} = User.create(@params)
    assert model_name(user, :singular) == "bruker"
    assert model_name(user, :plural) == "brukere"
  end
end