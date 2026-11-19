defmodule BrandoAdmin.Components.Assets.ProviderLibraryPanelTest do
  # "Add from <provider>", shared by the video picker and the Videos library:
  # the library's state on its owner's socket and the panel. Vimeo's API is
  # stubbed.
  use Brando.ConnCase

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Factory
  alias Brando.Videos.Uploaders.Vimeo
  alias BrandoAdmin.Components.Assets.ProviderLibraryPanel
  alias Phoenix.LiveView.Socket

  @library %{
    strategy: :vimeo,
    label: "Vimeo",
    search?: true,
    collections?: true,
    collections: [],
    collection: "",
    query: "",
    items: [],
    next: nil,
    loading?: true,
    error: nil,
    ref: nil
  }

  defp item(remote_id, extra \\ %{}) do
    Map.merge(
      %{
        remote_id: remote_id,
        title: "Clip #{remote_id}",
        thumbnail_url: nil,
        duration: 75.4,
        width: 1920,
        height: 1080,
        status: :ready,
        created_at: "2026-09-01T10:00:00Z",
        playable?: true,
        collection_id: nil,
        video_id: nil
      },
      extra
    )
  end

  defp socket(assigns), do: %Socket{assigns: Map.merge(%{__changed__: %{}}, assigns)}

  test "providers/2 offers none for a config that takes no external videos" do
    put_test_env(Vimeo, access_token: "vimeo-token")
    user = Factory.insert(:random_user, role: :superuser)

    assert [%{strategy: :vimeo, label: "Vimeo"}] = ProviderLibraryPanel.providers(user, true)
    assert ProviderLibraryPanel.providers(user, false) == []
  end

  describe "page_loaded/2" do
    test "fills the library from the page its last request asked for" do
      ref = make_ref()
      socket = socket(%{library: %{@library | ref: ref}})

      socket =
        ProviderLibraryPanel.page_loaded(socket, {:ok, {ref, nil, {:ok, %{items: [item("1")], next: "c2"}}, nil}})

      assert %{items: [%{remote_id: "1"}], next: "c2", loading?: false} = socket.assigns.library

      # A further page adds to it
      socket =
        ProviderLibraryPanel.page_loaded(socket, {:ok, {ref, "c2", {:ok, %{items: [item("2")], next: nil}}, nil}})

      assert Enum.map(socket.assigns.library.items, & &1.remote_id) == ["1", "2"]
    end

    test "drops a page for a request superseded since, or a library closed" do
      socket = socket(%{library: %{@library | ref: make_ref()}})
      page = {:ok, {make_ref(), nil, {:ok, %{items: [item("1")], next: nil}}, nil}}

      assert ProviderLibraryPanel.page_loaded(socket, page).assigns.library.items == []
      assert ProviderLibraryPanel.page_loaded(socket(%{library: nil}), page).assigns.library == nil
    end

    test "says when the provider fails or the listing crashes" do
      ref = make_ref()
      socket = socket(%{library: %{@library | ref: ref}})

      failed = ProviderLibraryPanel.page_loaded(socket, {:ok, {ref, nil, {:error, :not_found}, nil}})
      assert %{loading?: false, error: "Vimeo no longer has this video."} = failed.assigns.library

      crashed = ProviderLibraryPanel.page_loaded(socket, {:exit, :boom})
      assert crashed.assigns.library.error == "Could not reach Vimeo. Try again in a moment."
    end

    test "takes the collections read with the first page; without them, the library is one list" do
      ref = make_ref()
      socket = socket(%{library: %{@library | ref: ref, collections: nil}})
      page = {:ok, %{items: [item("1")], next: nil}}
      collections = [%{id: "11", name: "Client A", count: 6}]

      read = ProviderLibraryPanel.page_loaded(socket, {:ok, {ref, nil, page, {:ok, collections}}})
      assert read.assigns.library.collections == collections

      failed = ProviderLibraryPanel.page_loaded(socket, {:ok, {ref, nil, page, {:error, :timeout}}})
      assert %{collections: [], items: [_], error: nil} = failed.assigns.library

      assert ProviderLibraryPanel.page_loaded(socket, {:exit, :boom}).assigns.library.collections == []
    end
  end

  describe "search/2" do
    setup do
      put_test_env(Vimeo, access_token: "vimeo-token")
      collections = [%{id: "11", name: "Client A", count: 6}]
      %{socket: socket(%{library: %{@library | query: "dawn", collections: collections, items: [item("1")]}})}
    end

    test "lists the collection chosen, keeping the search", %{socket: socket} do
      socket = ProviderLibraryPanel.search(socket, %{"collection" => "11"})
      assert %{collection: "11", query: "dawn", items: [], loading?: true} = socket.assigns.library
    end

    test "searches the collection the form names, or all of them for one not listed", %{socket: socket} do
      socket = ProviderLibraryPanel.search(socket, %{"query" => " harbour ", "collection" => "11"})
      assert %{collection: "11", query: "harbour"} = socket.assigns.library

      socket = ProviderLibraryPanel.search(socket, %{"collection" => "../99"})
      assert %{collection: "", query: "harbour"} = socket.assigns.library
    end
  end

  test "search/2 and more/1 leave a closed library alone" do
    socket = socket(%{library: nil})
    assert ProviderLibraryPanel.search(socket, %{"query" => "harbour"}) == socket
    assert ProviderLibraryPanel.more(socket) == socket
    # Nothing further to list
    open = socket(%{library: %{@library | next: nil}})
    assert ProviderLibraryPanel.more(open) == open
  end

  test "add/4 refuses with no library open" do
    socket = socket(%{library: nil})
    assert {:error, ^socket} = ProviderLibraryPanel.add(socket, "1", nil, [])
  end

  test "error_message/2" do
    assert ProviderLibraryPanel.error_message(:busy, "Mux") =~ "being added or deleted elsewhere"
    assert ProviderLibraryPanel.error_message("Quota exceeded", "Mux") == "Quota exceeded"
    assert ProviderLibraryPanel.error_message(:timeout, "Mux") == "Could not reach Mux. Try again in a moment."
  end

  test "item_meta/1 gives the duration, size and day added" do
    assert ProviderLibraryPanel.item_meta(item("1")) == "1:15 · 1920 × 1080 · 2026-09-01"
    assert ProviderLibraryPanel.item_meta(item("1", %{duration: nil, width: nil, created_at: nil})) == ""
    assert ProviderLibraryPanel.item_meta(item("1"), "Client A") == "Client A · 1:15 · 1920 × 1080 · 2026-09-01"
  end

  describe "panel/1" do
    setup do
      %{
        items: [
          item("new"),
          item("held", %{video_id: 7}),
          item("encoding", %{status: :processing, playable?: false})
        ]
      }
    end

    test "offers Add, Select for a video Brando holds, and the state of one not ready", %{items: items} do
      html =
        render_component(&ProviderLibraryPanel.panel/1, id: "p", library: %{@library | items: items, loading?: false})

      assert [_] =
               Floki.find(Floki.parse_fragment!(html), ~s([data-remote-id="new"] button[phx-click="add_from_library"]))

      held = html |> Floki.parse_fragment!() |> Floki.find(~s([data-remote-id="held"]))
      assert Floki.text(held) =~ "In library"
      assert Floki.text(Floki.find(held, "button")) =~ "Select"

      assert html |> Floki.parse_fragment!() |> Floki.find(~s([data-remote-id="encoding"])) |> Floki.text() =~
               "Processing"

      assert html =~ "video-picker-library-header"
    end

    test "inside a modal: no heading of its own, and a held video is only marked", %{items: items} do
      html =
        render_component(&ProviderLibraryPanel.panel/1,
          id: "lib",
          library: %{@library | items: items, loading?: false},
          heading: false,
          select_existing: false
        )

      doc = Floki.parse_fragment!(html)
      assert Floki.find(doc, ".video-picker-library-header") == []
      assert [_] = Floki.find(doc, "section#lib-library.video-picker-library")
      assert Floki.text(Floki.find(doc, ".video-picker-library-lede")) =~ "Videos already in your Vimeo account."
      assert Floki.text(Floki.find(doc, ~s([data-remote-id="held"]))) =~ "In library"
      assert Floki.find(doc, ~s([data-remote-id="held"] button)) == []
    end

    test "no collection dropdown for a provider without collections", %{items: items} do
      html =
        render_component(&ProviderLibraryPanel.panel/1, id: "p", library: %{@library | items: items, loading?: false})

      doc = Floki.parse_fragment!(html)

      assert Floki.find(doc, "select") == []
      assert [_] = Floki.find(doc, "input#p-library-query")
    end
  end

  describe "panel/1 with collections" do
    setup do
      library = %{
        @library
        | strategy: :bunny,
          label: "Bunny Stream",
          loading?: false,
          collections: [%{id: "c-1", name: "Client A", count: 6}, %{id: "c-2", name: "Client B", count: nil}],
          items: [item("in-a", %{collection_id: "c-1"}), item("loose"), item("elsewhere", %{collection_id: "c-9"})]
      }

      %{library: library}
    end

    test "a dropdown on All videos, and each video names its collection", %{library: library} do
      doc = library |> render_library() |> Floki.parse_fragment!()

      assert [select] = Floki.find(doc, ~s(form select#p-library-collection[name="collection"]))
      assert Floki.attribute(select, "phx-change") == ["search_library"]
      assert Floki.attribute(select, "aria-label") == ["Collection"]

      assert select |> Floki.find("option") |> Enum.map(&String.trim(Floki.text(&1))) == [
               "All videos",
               "Client A · 6",
               "Client B"
             ]

      assert select |> Floki.find("option[selected]") |> Floki.attribute("value") == [""]

      assert meta(doc, "in-a") == "Client A · 1:15 · 1920 × 1080 · 2026-09-01"
      assert meta(doc, "loose") == "1:15 · 1920 × 1080 · 2026-09-01"
      assert meta(doc, "elsewhere") == "1:15 · 1920 × 1080 · 2026-09-01"
    end

    test "a collection chosen: selected, its videos not named, and an empty one said so", %{library: library} do
      doc = %{library | collection: "c-1"} |> render_library() |> Floki.parse_fragment!()

      assert doc |> Floki.find("option[selected]") |> Floki.attribute("value") == ["c-1"]
      assert meta(doc, "in-a") == "1:15 · 1920 × 1080 · 2026-09-01"

      empty = %{library | collection: "c-1", items: []} |> render_library() |> Floki.parse_fragment!()
      assert Floki.text(Floki.find(empty, ".video-picker-library-note")) =~ "No videos in this collection."

      folder = %{library | strategy: :vimeo, collection: "c-1", items: []} |> render_library() |> Floki.parse_fragment!()
      assert Floki.text(Floki.find(folder, ".video-picker-library-note")) =~ "No videos in this folder."
      assert Floki.attribute(Floki.find(folder, "select"), "aria-label") == ["Folder"]
    end

    test "a video in a folder not listed is named by its own", %{library: library} do
      items = [item("sub", %{collection_id: "c-9", collection_name: "Subfolder"})]
      doc = %{library | items: items} |> render_library() |> Floki.parse_fragment!()
      assert meta(doc, "sub") =~ "Subfolder · "
    end

    test "the dropdown alone, for a provider that does not search", %{library: library} do
      doc = %{library | search?: false} |> render_library() |> Floki.parse_fragment!()

      assert [_] = Floki.find(doc, "select")
      assert Floki.find(doc, "input[type=search]") == []
      assert Floki.find(doc, "button[type=submit]") == []
    end
  end

  defp render_library(library), do: render_component(&ProviderLibraryPanel.panel/1, id: "p", library: library)

  defp meta(doc, remote_id) do
    doc |> Floki.find(~s([data-remote-id="#{remote_id}"] .video-picker-library-meta)) |> Floki.text() |> String.trim()
  end
end
