defmodule Brando.Instagram.AccessTokenTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Instagram.AccessToken

  test "retrieve_token" do
    assert AccessToken.retrieve_token() == "abcd123"
    assert AccessToken.load_token == %{"access_token" => "abcd123"}
  end
end