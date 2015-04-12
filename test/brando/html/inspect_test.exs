defmodule Brando.HTML.InspectTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  import Brando.HTML.Inspect
  alias Brando.Users.Model.User
  alias Brando.News.Model.Post

  @user_params %{"avatar" => nil, "role" => ["2", "4"],
            "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
            "password" => "finimeze", "status" => "1",
            "submit" => "Submit", "username" => "zabuzasixu"}

  @post_params %{"avatar" => %Brando.Type.Image{credits: nil, optimized: false,
                                            path: "images/avatars/27i97a.jpeg",
                                            sizes: %{large: "images/avatars/large/27i97a.jpeg",
                                                     medium: "images/avatars/medium/27i97a.jpeg"},
                                            title: nil},
                 "creator_id" => 1,
                 "data" => "[{\"type\":\"text\",\"data\":{\"text\":\"zcxvxcv\"}}]",
                 "featured" => true,
                 "header" => "Header",
                 "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                 "language" => "no",
                 "lead" => "Asdf",
                 "meta_description" => nil,
                 "meta_keywords" => nil,
                 "publish_at" => nil,
                 "published" => false,
                 "slug" => "header",
                 "status" => :published}

  test "model/1" do
    assert {:ok, user} = User.create(@user_params)
    {:safe, ret} = model(user)
    assert ret =~ "zabuzasixu"
    assert ret =~ "Nita Bond"

    assert {:ok, post} = Post.create(@post_params, user)
    post = post |> Brando.get_repo.preload(:creator)
    {:safe, ret} = model(post)
    assert ret =~ "<i class=\"fa fa-times text-danger\">"
    assert ret =~ "Nita Bond"
    assert ret =~ "<p>zcxvxcv</p>"
  end

  test "model_repr/1" do
    assert {:ok, user} = User.create(@user_params)
    assert model_repr(user) == "Nita Bond (zabuzasixu)"
  end

  test "model_name/2" do
    assert {:ok, user} = User.create(@user_params)
    assert model_name(user, :singular) == "bruker"
    assert model_name(user, :plural) == "brukere"
  end
end