defmodule Brando.Utils.ModelTest do
  use ExUnit.Case, async: true
  use Plug.Test
  alias Brando.Utils

  test "transform_checkbox_vals/2" do
    params =
      %{"avatar" => "", "role" => ["2", "4"], "editor" => "on",
        "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
        "password" => "finimeze", "status" => "1",
        "submit" => "Submit", "username" => "zabuzasixu"}
    assert Utils.Model.transform_checkbox_vals(params, ~w(administrator editor)) ==
      %{"avatar" => "", "editor" => true, "email" => "fanogigyni@gmail.com",
        "full_name" => "Nita Bond", "password" => "finimeze", "role" => ["2", "4"],
        "status" => "1", "submit" => "Submit", "username" => "zabuzasixu"}
  end
end