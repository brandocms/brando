defmodule Brando.HTML.TablizeTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  import Brando.HTML.Tablize
  alias Brando.User
  alias Brando.Post

  @user_params %{"avatar" => nil, "role" => ["2", "4"],
            "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
            "password" => "finimeze", "username" => "zabuzasixu"}

  @image_map %Brando.Type.Image{credits: nil, optimized: false, path: "images/avatars/27i97a.jpeg", title: nil,
                                sizes: %{thumb: "images/avatars/thumb/27i97a.jpeg", medium: "images/avatars/medium/27i97a.jpeg"}}

  @post_params %{"avatar" => @image_map, "creator_id" => 1,
                 "data" => "[{\"type\":\"text\",\"data\":{\"text\":\"zcxvxcv\"}}]",
                 "featured" => true, "header" => "Header",
                 "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                 "language" => "no", "lead" => "Asdf",
                 "meta_description" => nil, "meta_keywords" => nil,
                 "publish_at" => nil, "published" => false,
                 "slug" => "header", "status" => :published}

  test "tablize/1" do
    assert {:ok, user} = User.create(@user_params)
    assert {:ok, post} = Post.create(@post_params, user)
    post = post |> Brando.repo.preload(:creator)
    helpers = [{"Vis bruker", "fa-search", :admin_user_path, :show, :id},
            {"Endre bruker", "fa-edit", :admin_user_path, :edit, :id},
            {"Slett bruker", "fa-trash", :admin_user_path, :delete_confirm, :id}]
    {:safe, ret} = tablize([post], helpers, check_or_x: [:meta_keywords], hide: [:updated_at, :inserted_at])
    assert ret =~ "<i class=\"fa fa-times text-danger\">"
    assert ret =~ "/admin/brukere/#{post.id}"
    assert ret =~ "/admin/brukere/#{post.id}/endre"
    assert ret =~ "/admin/brukere/#{post.id}/slett"
  end
end