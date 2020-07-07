defmodule Brando.AdminChannelTest do
  use Brando.ChannelCase, async: false
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Brando.Factory
  alias Brando.Integration.AdminChannel
  alias Brando.Integration.AdminSocket
  alias Brando.Integration.Endpoint

  @endpoint Endpoint

  setup do
    user = Factory.insert(:random_user)
    socket = socket(AdminSocket, "admin", %{})
    socket = Guardian.Phoenix.Socket.put_current_resource(socket, user)
    {:ok, socket} = AdminSocket.connect(%{"guardian_token" => "blerg"}, socket)
    {:ok, _, socket} = subscribe_and_join(socket, AdminChannel, "admin", %{})

    {:ok, %{socket: socket, user: user}}
  end

  test "pages:list_parents", %{socket: socket} do
    ref = push(socket, "pages:list_parents", %{})
    assert_reply ref, :ok, %{code: 200, parents: [%{name: "–", value: nil}]}

    Factory.insert(:page)

    ref = push(socket, "pages:list_parents", %{})

    assert_reply ref, :ok, %{
      code: 200,
      parents: [%{name: "–", value: nil}, %{name: _}]
    }
  end

  test "pages:list_templates", %{socket: socket} do
    ref = push(socket, "pages:list_templates", %{})

    assert_reply ref, :ok, %{
      code: 200,
      templates: [%{name: "index", value: "index.html"}, %{name: "show", value: "show.html"}]
    }
  end

  test "pages:sequence_pages", %{socket: socket} do
    p1 = Factory.insert(:page)
    p2 = Factory.insert(:page)
    p3 = Factory.insert(:page)

    assert p1.sequence == 0
    assert p2.sequence == 0
    assert p3.sequence == 0

    ref = push(socket, "pages:sequence_pages", %{"ids" => [p2.id, p3.id, p1.id]})
    assert_reply ref, :ok, %{code: 200}

    q =
      from t in Brando.Pages.Page,
        order_by: :sequence,
        select: [t.id]

    pages = Brando.repo().all(q)

    assert pages == [[p2.id], [p3.id], [p1.id]]
  end

  test "page:delete", %{socket: socket} do
    p1 = Factory.insert(:page)

    ref = push(socket, "page:delete", %{"id" => p1.id})
    assert_reply ref, :ok, %{code: 200}
  end

  test "page:duplicate", %{socket: socket} do
    p1 = Factory.insert(:page, data: [])

    ref = push(socket, "page:duplicate", %{"id" => p1.id})
    assert_reply ref, :ok, %{code: 200, page: page}
    refute page.id == p1
  end

  test "page:rerender", %{socket: socket} do
    p1 =
      Factory.insert(:page,
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
          }
        ]
      )

    ref = push(socket, "page:rerender", %{"id" => to_string(p1.id)})
    assert_reply ref, :ok, %{code: 200}
  end

  test "page:rerender_all", %{socket: socket} do
    _ =
      Factory.insert(:page,
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
          }
        ]
      )

    ref = push(socket, "page:rerender_all", %{})
    assert_reply ref, :ok, %{code: 200}
  end

  test "page_fragments:sequence_fragments", %{socket: socket} do
    p1 = Factory.insert(:page_fragment)
    p2 = Factory.insert(:page_fragment)
    p3 = Factory.insert(:page_fragment)

    assert p1.sequence == 0
    assert p2.sequence == 0
    assert p3.sequence == 0

    ref = push(socket, "page_fragments:sequence_fragments", %{"ids" => [p2.id, p3.id, p1.id]})
    assert_reply ref, :ok, %{code: 200}

    q =
      from t in Brando.Pages.PageFragment,
        order_by: :sequence,
        select: [t.id]

    pages = Brando.repo().all(q)

    assert pages == [[p2.id], [p3.id], [p1.id]]
  end

  test "page_fragment:duplicate", %{socket: socket} do
    p1 = Factory.insert(:page_fragment, data: [])

    ref = push(socket, "page_fragment:duplicate", %{"id" => p1.id})

    assert_reply ref, :ok, %{
      code: 200,
      page_fragment: %Brando.Pages.PageFragment{key: "header_kopi"}
    }
  end

  test "page_fragment:rerender", %{socket: socket} do
    p1 =
      Factory.insert(:page_fragment,
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
          }
        ]
      )

    ref = push(socket, "page_fragment:rerender", %{"id" => to_string(p1.id)})
    assert_reply ref, :ok, %{code: 200}
  end

  test "page_fragment:rerender_all", %{socket: socket} do
    _ =
      Factory.insert(:page_fragment,
        data: [
          %{
            "type" => "text",
            "data" => %{"text" => "**Some** text here.", "type" => "paragraph"}
          }
        ]
      )

    ref = push(socket, "page_fragment:rerender_all", %{})
    assert_reply ref, :ok, %{code: 200}
  end

  test "datasource:list_modules", %{socket: socket} do
    ref = push(socket, "datasource:list_modules", %{})
    assert_reply ref, :ok, %{code: 200, available_modules: []}
  end

  test "datasource:list_module_keys", %{socket: socket} do
    ref =
      push(socket, "datasource:list_module_keys", %{
        "module" => "Elixir.Brando.Integration.ModuleWithDatasource"
      })

    assert_reply ref, :ok, %{
      code: 200,
      available_module_keys: %{many: [:all], one: [], selection: [:featured]}
    }
  end

  test "datasource:list_available_entries", %{socket: socket} do
    ref =
      push(socket, "datasource:list_available_entries", %{
        "module" => "Elixir.Brando.Integration.ModuleWithDatasource",
        "query" => "featured"
      })

    assert_reply ref, :ok, %{
      code: 200,
      available_entries: [%{id: 1, label: "label 1"}, %{id: 2, label: "label 2"}]
    }
  end

  test "templates:list_templates", %{socket: socket} do
    _ = Factory.insert(:template)
    ref = push(socket, "templates:list_templates", %{})

    assert_reply ref, :ok, %{code: 200, templates: [%{id: _, name: " - "}]}
  end

  test "livepreview:initialize", %{socket: socket} do
    # p1 = Factory.insert(:page)
    entry = %{"title" => "Page title!"}

    ref =
      push(socket, "livepreview:initialize", %{
        "schema" => "Brando.Users.User",
        "entry" => entry,
        "key" => "data",
        "prop" => "page"
      })

    assert_reply ref, :error, %{code: 404, message: "Initialization failed."}

    ref =
      push(socket, "livepreview:initialize", %{
        "schema" => "Brando.Pages.Page",
        "entry" => entry,
        "key" => "data",
        "prop" => "page"
      })

    assert_reply ref, :ok, %{code: 200, cache_key: cache_key}

    ref =
      push(socket, "livepreview:render", %{
        "schema" => "Brando.Pages.Page",
        "entry" => entry,
        "key" => "data",
        "prop" => "page",
        "cache_key" => cache_key
      })

    assert_reply ref, :ok, %{code: 200, cache_key: ^cache_key}
  end
end
