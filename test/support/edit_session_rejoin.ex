defmodule Brando.EditSessionRejoin do
  @moduledoc """
  Crash an entry's edit session and bring its editors back the way
  production does, through real LiveViews (`Brando.LiveCase`).

  A rejoin test must take the path production takes: each editor's
  BlockField handles the session's `:DOWN` and joins again with the rows it
  loaded and what it holds (`BlockField.rejoin_session/1`). A test that calls
  `Brando.EditSession.join/4` with state it built (fresh rows as the base, a
  held state the editor never had) can stay green while that path is broken.

      page = rows_page!(user)
      a = open(conn, page)
      b = open(other_conn, page)
      hold(b)                    # B handles the :DOWN late
      kill_session(page)         # A rejoins at once and seeds the new session
      await_joined(a, page)
      release(b)                 # B rejoins now, with what it held
      await_joined(b, page)

  * `rows_page!/1` — a page with one block holding table rows, a gallery
    ref and a var, the lists a rejoin merges by row.
  * `hold/1`, `release/1` — keep a LiveView from handling messages, so it
    handles the session's `:DOWN` (or anything else) late.
  * `hold_session/1` — keep the session from handling messages: ops the
    editors cast meanwhile stay unconfirmed, and are lost with it when
    `kill_session/1` follows.
  * `kill_session/1` — kill the session as a crash would; returns once the
    process is gone.
  * `await_joined/2` — wait until a LiveView's block field has joined the
    entry's current session.
  * `shown_rows/3` — the ids of a block's rows (`"table_rows"`, `"refs"`,
    `"vars"`) a LiveView's form shows.
  """

  import ExUnit.Assertions, only: [flunk: 1]
  import Phoenix.LiveViewTest, only: [render: 1]

  alias Brando.Content.Block
  alias Brando.EditSession
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo

  @doc """
  A page with one module block holding two table rows (a `cell` var each),
  a `gallery` ref with two images and a `heading` var. Returns `%{page:,
  uid:}`, `uid` being the block's.
  """
  def rows_page!(user) do
    uid = fn -> Brando.Utils.generate_uid() end
    template = Repo.insert!(%Brando.Content.TableTemplate{uid: uid.(), name: "Rows"})

    Repo.insert!(%Brando.Content.Var{
      type: :string,
      key: "cell",
      label: %{"en" => "Cell"},
      table_template_id: template.id
    })

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Rows"},
          namespace: %{"en" => "Content"},
          help_text: %{"en" => "Rows"},
          code: "<div>{{ heading }}{% ref refs.gallery %}</div>",
          refs: [%{name: "gallery", uid: uid.(), data: %{type: "gallery", data: %{}}}],
          vars: [%{type: "string", key: "heading", label: "Heading", value: "Heading"}],
          table_template_id: template.id
        ),
        user
      )

    gallery =
      Repo.insert!(%Brando.Galleries.Gallery{
        gallery_objects:
          for n <- 0..1 do
            %Brando.Galleries.GalleryObject{image_id: Factory.insert(:image, creator_id: user.id).id, sequence: n}
          end
      })

    cell = fn text -> %{"type" => "string", "key" => "cell", "label" => "Cell", "value" => text} end
    page = Factory.insert(:page, creator: user, title: "Rows", uri: "rows-#{System.unique_integer([:positive])}")

    block =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => uid.(),
          "type" => "module",
          "module_id" => module.id,
          "creator_id" => user.id,
          "source" => to_string(Page.Blocks),
          "refs" => [
            %{
              "uid" => uid.(),
              "name" => "gallery",
              "gallery_id" => gallery.id,
              "data" => %{"type" => "gallery", "data" => %{}}
            }
          ],
          "vars" => [%{"type" => "string", "key" => "heading", "label" => "Heading", "value" => "Heading"}],
          "table_rows" => [%{"vars" => [cell.("First")]}, %{"vars" => [cell.("Second")]}]
        },
        user
      )
      |> Repo.insert!()

    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    %{page: page, uid: block.uid}
  end

  @doc "Keep `view` from handling messages until `release/1`."
  def hold(view), do: :sys.suspend(view.pid)

  @doc "Let `view` handle what reached it while it was held."
  def release(view), do: :sys.resume(view.pid)

  @doc "Keep the entry's session from handling messages until it is killed."
  def hold_session(entry), do: entry |> session() |> :sys.suspend()

  @doc """
  Kill the entry's session as a crash would. The editors' block fields get
  `:DOWN` and rejoin (`await_joined/2`). Returns the killed process.
  """
  def kill_session(entry) do
    pid = session(entry) || flunk("the entry has no edit session")
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> pid
    after
      2_000 -> flunk("the edit session did not go")
    end
  end

  @doc """
  Wait until `view`'s block field has joined the entry's current session,
  which only `BlockField.rejoin_session/1` (or a fresh mount) does.
  """
  def await_joined(view, entry, tries \\ 150) do
    pid = session(entry)

    cond do
      pid && Map.has_key?(:sys.get_state(pid).clients, view.pid) -> pid
      tries == 0 -> flunk("the editor never joined the entry's edit session")
      true -> Process.sleep(20) && await_joined(view, entry, tries - 1)
    end
  end

  @doc """
  The ids of the rows of block `uid` a LiveView's form shows, in order, for
  `relation` (`"table_rows"`, `"refs"` or `"vars"`).
  """
  def shown_rows(view, uid, relation) do
    view
    |> render()
    |> Brando.LiveCase.form_params("#entry_block_form-#{uid}")
    |> get_in(["entry_block", "block", relation])
    |> Kernel.||(%{})
    |> Enum.sort_by(fn {index, _row} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, row} -> row["id"] end)
  end

  defp session(%{__struct__: schema, id: id} = entry),
    do: EditSession.whereis(EditSession.ref(schema, id, Map.get(entry, :language)))
end
