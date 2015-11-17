defmodule Brando.HTML.TablizeTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  import Brando.HTML.Tablize
  import Brando.I18n
  alias Brando.Page

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
    assert {:ok, page} = Page.create(@page_params, user)
    page = page |> Brando.repo.preload([:creator, :parent, :children])

    assert {:ok, page2} = Page.create(Map.put(@page_params, "language", "nb"), user)
    child_params =
      @page_params
      |> Map.put("parent_id", page2.id)
      |> Map.put("title", "Child title")
    assert {:ok, _} = Page.create(child_params, user)

    pages =
      Brando.Page
      |> Brando.Page.with_parents_and_children
      |> Brando.repo.all

    helpers = [{"Show user", "fa-search", :admin_user_path, :show, :id},
               {"Edit user", "fa-edit", :admin_user_path, :edit, :id},
               {"Delete user", "fa-trash",
                :admin_user_path, :delete_confirm, :id, :superuser},
               {"List test", "fa-trash",
                :test_path, :test, [:id, :language], :superuser}]

    {:safe, ret} = tablize(@conn, pages, helpers, check_or_x: [:meta_keywords],
                           hide: [:updated_at, :inserted_at, :parent])

    ret = ret |> IO.iodata_to_binary
    assert ret =~ "<i class=\"fa fa-times text-danger\">"
    assert ret =~ "/admin/users/#{page.id}"
    assert ret =~ "/admin/users/#{page.id}/edit"
    assert ret =~ "/admin/users/#{page.id}/delete"
    assert ret =~ "/test123/#{page.id}/#{page.language}"

    {:safe, ret} = tablize(@conn, [page], helpers,
                           check_or_x: [:meta_keywords],
                           hide: [:updated_at, :inserted_at, :parent],
                           colgroup: [100, 100])
    ret = ret |> IO.iodata_to_binary
    assert ret =~ "colgroup"
    assert ret =~ "width: 100px"

    {:safe, ret} = tablize(@conn, [page], helpers, filter: true, hide: [:parent])

    ret = ret |> IO.iodata_to_binary
    assert ret
           =~ ~s(<input type="text" placeholder="Filter" id="filter-input" />)

    pages =
      Brando.Page
      |> Brando.Page.with_parents_and_children
      |> Brando.repo.all

    {:safe, ret} = tablize(@conn, pages, helpers,
                           split_by: :language,
                           children: :children,
                           hide: [:parent, :children])

    ret = ret |> IO.iodata_to_binary
    assert ret =~ "nb"
    assert ret =~ "en"
    assert ret =~ "Child title"

    {:safe, ret} = tablize(nil, nil, nil, nil)
    assert ret == "<p>No results</p>"
  end
end
