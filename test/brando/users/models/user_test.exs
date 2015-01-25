defmodule Brando.Integration.UserTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  alias Brando.Users.Model.User
  @params %{"avatar" => "", "role" => ["2", "4"],
            "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
            "password" => "finimeze", "status" => "1",
            "submit" => "Submit", "username" => "zabuzasixu"}

  test "create/1 and update/1" do
    assert {:ok, user} = User.create(@params)

    params = %{"full_name" => "Elvis Presley"}
    assert {:ok, updated_user} = User.update(user, params)
    assert updated_user.full_name == "Elvis Presley"

    old_pass = updated_user.password
    params = %{"password" => "newpass"}
    assert {:ok, updated_password_user} = User.update(updated_user, params)
    refute old_pass == updated_password_user.password
    refute updated_password_user.password == "newpass"
  end

  test "create/1 errors" do
    {_v, params} = Dict.pop @params, "email"
    assert {:error, err} = User.create(params)
    assert err == [email: :required]
  end

  test "update/1 errors" do
    assert {:ok, user} = User.create(@params)
    params = Dict.put @params, "email", "asdf"
    assert {:error, err} = User.update(user, params)
    assert err == [email: :format]
  end

  test "update_field/2" do
    assert {:ok, user} = User.create(@params)
    assert {:ok, model} = User.update_field(user, [full_name: "James Bond"])
    assert model.full_name == "James Bond"
  end

  test "transform_checkbox_vals/2" do
    params =
      %{"avatar" => "", "role" => ["2", "4"], "editor" => "on",
        "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
        "password" => "finimeze", "status" => "1",
        "submit" => "Submit", "username" => "zabuzasixu"}
    assert User.transform_checkbox_vals(params, ~w(administrator editor)) ==
      %{"avatar" => "", "editor" => true, "email" => "fanogigyni@gmail.com",
        "full_name" => "Nita Bond", "password" => "finimeze", "role" => ["2", "4"],
        "status" => "1", "submit" => "Submit", "username" => "zabuzasixu"}
  end

  test "get/1" do
    assert {:ok, user} = User.create(@params)
    refute User.get(username: "zabuzasixu") == nil
    assert User.get(username: "elvis") == nil
    refute User.get(email: "fanogigyni@gmail.com") == nil
    assert User.get(email: "elvis@hotmail.com") == nil
    assert User.get(id: user.id) == user
  end

  test "delete/1" do
    assert {:ok, user} = User.create(@params)
    User.delete(user)
    assert User.get(username: "zabuzasixu") == nil
    assert User.get(email: "fanogigyni@gmail.com") == nil
  end

  test "all/0" do
    assert User.all == []
    assert {:ok, _user} = User.create(@params)
    refute User.all == []
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

  test "check_for_uploads/2 success" do
    assert {:ok, user} = User.create(@params)
    up_plug =
      %Plug.Upload{content_type: "image/png",
                   filename: "sample.png",
                   path: "#{Path.expand("../../../", __DIR__)}/fixtures/sample.png"}
    up_params = Dict.put(@params, "avatar", up_plug)
    assert {:ok, dict} = User.check_for_uploads(user, up_params)
    user = User.get(email: "fanogigyni@gmail.com")
    assert user.avatar == elem(dict[:file], 1)
    assert File.exists?(Path.join([Brando.Mugshots.Utils.get_media_abspath, elem(dict[:file], 1)]))
    User.delete(user)
    refute File.exists?(Path.join([Brando.Mugshots.Utils.get_media_abspath, elem(dict[:file], 1)]))
  end

  test "check_for_uploads/2 error" do
    assert {:ok, user} = User.create(@params)
    up_plug =
      %Plug.Upload{content_type: "image/png",
                   filename: "",
                   path: "#{Path.expand("../../../", __DIR__)}/fixtures/sample.png"}
    up_params = Dict.put(@params, "avatar", up_plug)
    assert {:errors, _dict} = User.check_for_uploads(user, up_params)
  end

  test "check_for_uploads/2 format error" do
    assert {:ok, user} = User.create(@params)
    up_plug =
      %Plug.Upload{content_type: "image/gif",
                   filename: "sample.gif",
                   path: "#{Path.expand("../../../", __DIR__)}/fixtures/sample.png"}
    up_params = Dict.put(@params, "avatar", up_plug)
    assert {:errors, dict} = User.check_for_uploads(user, up_params)
    assert dict == [error: {:avatar, "Ikke gyldig filformat (image/gif)"}]
  end

  test "check_for_uploads/2 copy error" do
    assert {:ok, user} = User.create(@params)
    up_plug =
      %Plug.Upload{content_type: "image/png",
                   filename: "sample.png",
                   path: "#{Path.expand("../../../", __DIR__)}/fixtures/non_existant.png"}
    up_params = Dict.put(@params, "avatar", up_plug)
    assert {:errors, dict} = User.check_for_uploads(user, up_params)
    assert dict == [error: {:avatar, :enoent}]
  end

  test "check_for_uploads/2 noupload" do
    assert {:ok, user} = User.create(@params)
    assert :nouploads = User.check_for_uploads(user, @params)
  end
end