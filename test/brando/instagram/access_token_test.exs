defmodule Brando.Instagram.AccessTokenTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Instagram.AccessToken

  setup do
    File.rm_rf!(Path.join([Mix.Project.app_path, "tmp"]))
    :ok
  end

  test "retrieve_token" do
    assert AccessToken.load_token == "abcd123"
    assert AccessToken.load_token == "abcd123"
  end
end