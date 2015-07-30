defmodule Brando.Integration.UserTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  alias Brando.User

  @params %{"avatar" => nil, "role" => ["2", "4"], "language" => "no",
            "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
            "password" => "finimeze", "status" => "1",
            "submit" => "Submit", "username" => "zabuzasixu"}

  test "create/1 and update/1" do
    assert {:ok, user} = User.create(@params)

    assert {:ok, updated_user} = User.update(user, %{"full_name" => "Elvis Presley"})
    assert updated_user.full_name == "Elvis Presley"

    old_pass = updated_user.password
    assert {:ok, updated_password_user} = User.update(updated_user, %{"password" => "newpass"})
    refute old_pass == updated_password_user.password
    refute updated_password_user.password == "newpass"
  end

  test "create/1 errors" do
    {_v, params} = Dict.pop @params, "email"
    assert {:error, err} = User.create(params)
    assert err == [email: "can't be blank"]
  end

  test "update/1 errors" do
    assert {:ok, user} = User.create(@params)
    params = Dict.put @params, "email", "asdf"
    assert {:error, err} = User.update(user, params)
    assert err == [email: "has invalid format"]
  end

  test "get/1" do
    assert {:ok, user} = User.create(@params)
    refute Brando.repo.get_by(User, username: "zabuzasixu") == nil
    assert Brando.repo.get_by(User, username: "elvis") == nil
    refute Brando.repo.get_by(User, email: "fanogigyni@gmail.com") == nil
    assert Brando.repo.get_by(User, email: "elvis@hotmail.com") == nil
    assert Brando.repo.get_by(User, id: user.id) == user
  end

  test "delete/1" do
    assert {:ok, user} = User.create(@params)
    User.delete(user)
    assert Brando.repo.get_by(User, username: "zabuzasixu") == nil
    assert Brando.repo.get_by(User, email: "fanogigyni@gmail.com") == nil
  end

  test "all/0" do
    assert Brando.repo.all(User) == []
    assert {:ok, _user} = User.create(@params)
    refute Brando.repo.all(User) == []
  end

  test "auth?/2" do
    assert {:ok, user} = User.create(@params)
    assert User.auth?(user, "finimeze")
    refute User.auth?(user, "finimeze123")
  end

  test "set_last_login/1" do
    assert {:ok, user} = User.create(@params)
    new_user = User.set_last_login(user)
    refute user.last_login == new_user.last_login
  end

  test "has_role?/1" do
    assert {:ok, user} = User.create(@params)
    assert User.has_role?(user, :superuser)
    assert User.has_role?(user, :admin)
    refute User.has_role?(user, :staff)
  end

  test "check_for_uploads/2 error" do
    assert {:ok, user} = User.create(@params)
    up_plug =
      %Plug.Upload{content_type: "image/png", filename: "",
                   path: Path.expand("../../../", __DIR__) <> "/fixtures/sample.png"}
    up_params = Dict.put(@params, "avatar", up_plug)
    assert_raise Brando.Exception.UploadError,
                 "Blankt filnavn gitt under opplasting. Pass på at du har et gyldig filnavn.",
                 fn -> User.check_for_uploads(user, up_params)
    end
  end

  test "check_for_uploads/2 format error" do
    assert {:ok, user} = User.create(@params)
    up_plug =
      %Plug.Upload{content_type: "image/gif", filename: "sample.gif",
                   path: Path.expand("../../../", __DIR__) <> "/fixtures/sample.png"}
    up_params = Dict.put(@params, "avatar", up_plug)
    assert_raise Brando.Exception.UploadError,
                 fn -> User.check_for_uploads(user, up_params) end
  end

  test "check_for_uploads/2 copy error" do
    assert {:ok, user} = User.create(@params)
    up_plug =
      %Plug.Upload{content_type: "image/png", filename: "sample.png",
                   path: Path.expand("../../../", __DIR__) <> "/fixtures/non_existant.png"}
    up_params = Dict.put(@params, "avatar", up_plug)
    assert_raise Brando.Exception.UploadError,
                 "Feil under kopiering -> :enoent",
                 fn -> User.check_for_uploads(user, up_params)
    end
  end

  test "check_for_uploads/2 noupload" do
    assert {:ok, user} = User.create(@params)
    assert [] = User.check_for_uploads(user, @params)
  end
end