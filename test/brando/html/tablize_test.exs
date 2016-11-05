defmodule Brando.HTML.TablizeTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  import Brando.HTML.Tablize
  import Brando.I18n
  alias Brando.Factory

  @conn %Plug.Conn{private: %{guardian_default_resource: %{role: [:superuser]}}}
        |> assign_language("nb")

  test "tablize/4" do
    user = Factory.insert(:user)

    helpers = [
      {"Show user", "fa-search", :admin_user_path, :show, :id},
      {"Edit user", "fa-edit", :admin_user_path, :edit, :id},
      {"Delete user", "fa-trash", :admin_user_path, :delete_confirm, :id, :superuser},
      {"List test", "fa-trash", :test_path, :test, [:id, :language], :superuser}
    ]

    {:safe, ret} = tablize(@conn, [user], helpers, check_or_x: [:meta_keywords],
                           hide: [:updated_at, :inserted_at, :parent])

    ret = IO.iodata_to_binary(ret)

    assert ret =~ ~s(censored)
    assert ret =~ ~s(/media/images/avatars/thumb/27i97a.jpeg)
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

    assert ret =~ ~s(<input type="text" placeholder="Filter" id="filter-input" />)

    {:safe, ret} = tablize(@conn, [user], helpers,
                           split_by: :language,
                           children: :children,
                           hide: [:parent, :children])

    ret        = IO.iodata_to_binary(ret)
    assert ret =~ "flag-en"

    {:safe, ret} = tablize(nil, nil, nil, nil)

    assert ret == "<p>No results</p>"

    {:safe, ret} = tablize(@conn, [user], helpers, smart_fields: [{"custom header", __MODULE__, :smart}])

    ret        = IO.iodata_to_binary(ret)
    assert ret =~ "<th>custom header</th>"
    assert ret =~ ~s(<td data-field="smart-field" class="text-center">jamesw</td>)
  end

  def smart(arg) do
    arg.username
  end
end
