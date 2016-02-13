defmodule Brando.HTML.TablizeTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  import Brando.HTML.Tablize
  import Brando.I18n

  @image_map %Brando.Type.Image{credits: nil, optimized: false,
                                path: "images/avatars/27i97a.jpeg", title: nil,
                                sizes: %{
                                  thumb: "images/avatars/thumb/27i97a.jpeg",
                                  medium: "images/avatars/medium/27i97a.jpeg"}}
  @conn %Plug.Conn{private: %{plug_session: %{"current_user" =>
                  %{role: [:superuser]}}}} |> assign_language("nb")
  @page_params %{"avatar" => @image_map,
                 "key" => "key/here",
                 "data" => "[{\"type\":\"text\",\"data\":" <>
                 "{\"text\":\"zcxvxcv\",\"type\":\"paragraph\"}}]",
                 "featured" => true, "title" => "Header",
                 "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                 "language" => "nb", "lead" => "Asdf",
                 "parent_id" => nil,
                 "meta_description" => nil, "meta_keywords" => nil,
                 "publish_at" => nil, "published" => false,
                 "slug" => "header", "status" => :published}

  test "tablize/4" do
    user = Forge.saved_user(TestRepo)

    users = Brando.repo.all(Brando.User)

    helpers = [{"Show user", "fa-search", :admin_user_path, :show, :id},
               {"Edit user", "fa-edit", :admin_user_path, :edit, :id},
               {"Delete user", "fa-trash",
                :admin_user_path, :delete_confirm, :id, :superuser},
               {"List test", "fa-trash",
                :test_path, :test, [:id, :language], :superuser}]

    {:safe, ret} = tablize(@conn, users, helpers, check_or_x: [:meta_keywords],
                           hide: [:updated_at, :inserted_at, :parent])

    ret = IO.iodata_to_binary(ret)
    assert ret =~ ~s(No connected image)
    assert ret =~ ~s(href="/admin/users/#{user.id}")
    assert ret =~ ~s(href="/admin/users/#{user.id}/edit")
    assert ret =~ ~s(href="/admin/users/#{user.id}/delete")

    {:safe, ret} = tablize(@conn, [user], helpers,
                           check_or_x: [:meta_keywords],
                           hide: [:updated_at, :inserted_at, :parent],
                           colgroup: [100, 100])
    ret = IO.iodata_to_binary(ret)
    assert ret =~ "colgroup"
    assert ret =~ "width: 100px"

    {:safe, ret} = tablize(@conn, [user], helpers, filter: true, hide: [:parent])

    ret = IO.iodata_to_binary(ret)
    assert ret
           =~ ~s(<input type="text" placeholder="Filter" id="filter-input" />)

    {:safe, ret} = tablize(@conn, users, helpers,
                           split_by: :language,
                           children: :children,
                           hide: [:parent, :children])

    ret = IO.iodata_to_binary(ret)
    assert ret =~ "flag-en"

    {:safe, ret} = tablize(nil, nil, nil, nil)
    assert ret == "<p>No results</p>"
  end
end
