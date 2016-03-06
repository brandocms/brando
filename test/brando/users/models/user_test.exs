defmodule Brando.Integration.UserTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  alias Brando.User

  @params %{"avatar" => nil, "role" => ["2", "4"], "language" => "nb",
            "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
            "password" => "finimeze", "status" => "1",
            "submit" => "Submit", "username" => "zabuzasixu"}

  test "create/1 and update/1" do
    assert {:ok, user} = create_user(@params)

    assert {:ok, updated_user}
           = User.update(user, %{"full_name" => "Elvis Presley"}) |> Brando.repo.update
    assert updated_user.full_name
           == "Elvis Presley"

    old_pass = updated_user.password
    assert {:ok, updated_password_user}
           = User.update(updated_user, %{"password" => "newpass"}) |> Brando.repo.update
    refute old_pass
           == updated_password_user.password
    refute updated_password_user.password
           == "newpass"
  end

  test "create/1 errors" do
    {_v, params} = Dict.pop @params, "email"
    assert {:error, changeset} = create_user(params)
    assert changeset.errors == [email: "can't be blank"]
  end

  test "update/1 errors" do
    assert {:ok, user} = create_user(@params)
    params = Dict.put @params, "email", "asdf"
    assert {:error, changeset} = User.update(user, params) |> Brando.repo.update
    assert changeset.errors == [email: "has invalid format"]
  end

  test "auth?/2" do
    assert {:ok, user} = create_user(@params)
    assert User.auth?(user, "finimeze")
    refute User.auth?(user, "finimeze123")
  end

  test "set_last_login/1" do
    assert {:ok, user} = create_user(@params)
    new_user = User.set_last_login(user)
    refute user.last_login == new_user.last_login
  end

  test "role?/1" do
    assert {:ok, user} = create_user(@params)
    assert User.role?(user, :superuser)
    assert User.role?(user, :admin)
    refute User.role?(user, :staff)
  end

  test "check_for_uploads/2 error" do
    assert {:ok, user} = create_user(@params)
    up_plug =
      %Plug.Upload{content_type: "image/png", filename: "",
                   path: Path.expand("../../../", __DIR__) <>
                         "/fixtures/sample.png"}
    up_params = Dict.put(@params, "avatar", up_plug)
    assert_raise Brando.Exception.UploadError,
                 "Empty filename given. Make sure you have a valid filename.",
                 fn -> User.check_for_uploads(user, up_params)
    end
  end

  test "check_for_uploads/2 format error" do
    assert {:ok, user} = create_user(@params)
    up_plug =
      %Plug.Upload{content_type: "image/gif", filename: "sample.gif",
                   path: Path.expand("../../../", __DIR__) <>
                         "/fixtures/sample.png"}
    up_params = Dict.put(@params, "avatar", up_plug)
    assert_raise Brando.Exception.UploadError,
                 fn -> User.check_for_uploads(user, up_params) end
  end

  test "check_for_uploads/2 copy error" do
    assert {:ok, user} = create_user(@params)
    up_plug =
      %Plug.Upload{content_type: "image/png", filename: "sample.png",
                   path: Path.expand("../../../", __DIR__) <>
                         "/fixtures/non_existant.png"}
    up_params = Dict.put(@params, "avatar", up_plug)
    assert_raise Brando.Exception.UploadError,
                 ~r/Error while copying -> :enoent/,
                 fn -> User.check_for_uploads(user, up_params)
    end
  end

  test "check_for_uploads/2 noupload" do
    assert {:ok, user} = create_user(@params)
    assert {:ok, []} = User.check_for_uploads(user, @params)
  end
end
