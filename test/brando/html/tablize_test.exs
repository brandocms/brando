defmodule Brando.HTML.TablizeTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  import Brando.HTML.Tablize
  import Brando.I18n
  alias Brando.Post

  @image_map %Brando.Type.Image{credits: nil, optimized: false,
                                path: "images/avatars/27i97a.jpeg", title: nil,
                                sizes: %{
                                  thumb: "images/avatars/thumb/27i97a.jpeg",
                                  medium: "images/avatars/medium/27i97a.jpeg"}}
  @conn %Plug.Conn{private: %{plug_session: %{"current_user" =>
                  %{role: [:superuser]}}}} |> assign_language("nb")
  @post_params %{"avatar" => @image_map,
                 "data" => "[{\"type\":\"text\",\"data\":" <>
                 "{\"text\":\"zcxvxcv\",\"type\":\"paragraph\"}}]",
                 "featured" => true, "header" => "Header",
                 "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                 "language" => "nb", "lead" => "Asdf",
                 "meta_description" => nil, "meta_keywords" => nil,
                 "publish_at" => nil, "published" => false,
                 "slug" => "header", "status" => :published}

  test "tablize/4" do
    user = Forge.saved_user(TestRepo)
    assert {:ok, post} = Post.create(@post_params, user)
    post = post |> Brando.repo.preload(:creator)

    assert {:ok, post2} = Post.create(Map.put(@post_params, "language", "nb"), user)
    post2 = post2 |> Brando.repo.preload(:creator)

    helpers = [{"Show user", "fa-search", :admin_user_path, :show, :id},
               {"Edit user", "fa-edit", :admin_user_path, :edit, :id},
               {"Delete user", "fa-trash",
                :admin_user_path, :delete_confirm, :id, :superuser}]
    {:safe, ret} = tablize(@conn, [post], helpers, check_or_x: [:meta_keywords],
                           hide: [:updated_at, :inserted_at])

    ret = ret |> IO.iodata_to_binary
    assert ret =~ "<i class=\"fa fa-times text-danger\">"
    assert ret =~ "/admin/users/#{post.id}"
    assert ret =~ "/admin/users/#{post.id}/edit"
    assert ret =~ "/admin/users/#{post.id}/delete"

    {:safe, ret} = tablize(@conn, [post], helpers, check_or_x: [:meta_keywords],
                           hide: [:updated_at, :inserted_at], colgroup: [100, 100])
    ret = ret |> IO.iodata_to_binary
    assert ret =~ "colgroup"
    assert ret =~ "width: 100px"

    {:safe, ret} = tablize(@conn, [post], helpers, filter: true)

    ret = ret |> IO.iodata_to_binary
    assert ret
           =~ ~s(<input type="text" placeholder="Filter" id="filter-input" />)

    {:safe, ret} = tablize(@conn, [post, post2], helpers, split_by: :language)
    ret = ret |> IO.iodata_to_binary
    assert ret =~ "nb"
    assert ret =~ "en"

    {:safe, ret} = tablize(nil, nil, nil, nil)
    assert ret == "<p>No results</p>"
  end
end
