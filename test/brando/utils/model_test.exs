defmodule Brando.Utils.ModelTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  use Plug.Test
  alias Brando.Utils
  alias Brando.Users.Model.User

  @params %{"avatar" => nil, "role" => ["2", "4"],
            "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
            "password" => "finimeze", "status" => "1",
            "submit" => "Submit", "username" => "zabuzasixu"}

  test "transform_checkbox_vals/2" do
    params =
      %{"avatar" => nil, "role" => ["2", "4"], "editor" => "on",
        "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
        "password" => "finimeze", "status" => "1",
        "submit" => "Submit", "username" => "zabuzasixu"}
    assert Utils.Model.transform_checkbox_vals(params, ~w(administrator editor)) ==
      %{"avatar" => nil, "editor" => true, "email" => "fanogigyni@gmail.com",
        "full_name" => "Nita Bond", "password" => "finimeze", "role" => ["2", "4"],
        "status" => "1", "submit" => "Submit", "username" => "zabuzasixu"}
  end

  test "update_field/2" do
    assert {:ok, user} = User.create(@params)
    assert {:ok, model} = Utils.Model.update_field(user, [full_name: "James Bond"])
    assert model.full_name == "James Bond"
  end
end