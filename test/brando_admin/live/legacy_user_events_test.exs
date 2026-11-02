defmodule BrandoAdmin.LegacyUserEventsTest do
  # A legacy `:user` account reads and exports, and writes nothing but its own
  # profile: each write below, sent over a real LiveView socket, leaves the data
  # alone for that role and still works for an editor. See
  # `BrandoAdmin.Authorization.Events`; `event_classification_test.exs` holds
  # every event to the same table.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content.Block
  alias Brando.EditSession
  alias Brando.EditSessionEditors, as: Editors
  alias Brando.Images.Image
  alias Brando.ListingViews
  alias Brando.Pages.Page
  alias Brando.Publisher
  alias Brando.Repo
  alias Brando.Revisions
  alias Brando.Revisions.Revision
  alias Brando.Test.Users, as: TestUsers
  alias BrandoAdmin.Images.FolderBrowser

  setup do
    owner = TestUsers.insert_user(role: :superuser)
    user = TestUsers.insert_user(role: :user)
    editor = TestUsers.insert_user(role: :editor)

    page = Factory.insert(:page, creator: owner, title: "Om oss", uri: "om-oss", status: :draft)

    %{
      owner: owner,
      user: user,
      editor: editor,
      page: page,
      user_conn: log_in_user(Phoenix.ConnTest.build_conn(), user),
      editor_conn: log_in_user(Phoenix.ConnTest.build_conn(), editor)
    }
  end

  defp status(page), do: Repo.get!(Page, page.id).status

  defp demote(user), do: Repo.update!(Ecto.Changeset.change(user, role: :user))

  defp form_assigns(view) do
    {components, _, _} = :sys.get_state(view.pid).components

    Enum.find_value(components, fn
      {_cid, {BrandoAdmin.Components.Form, _id, assigns, _private, _prints}} -> assigns
      _ -> nil
    end)
  end

  # The save runs once the blocks arrive; it ends with `processing` off,
  # unless it crashed the form first.
  defp await_saved_or_refused(view, tries \\ 100) do
    cond do
      not Process.alive?(view.pid) -> :ok
      not form_assigns(view).processing -> :ok
      tries == 0 -> flunk("the save never finished")
      true -> Process.sleep(20) && await_saved_or_refused(view, tries - 1)
    end
  end

  defp await_editing_tab(view, tries \\ 100) do
    cond do
      form_assigns(view).tab_editing? -> :ok
      tries == 0 -> flunk("the tab never came to edit")
      true -> Process.sleep(20) && await_editing_tab(view, tries - 1)
    end
  end

  # The test process is linked to the view, and goes on.
  defp assert_event_ends_view(view, fun) do
    Process.flag(:trap_exit, true)
    ref = Process.monitor(view.pid)
    catch_exit(fun.())
    assert_receive {:DOWN, ^ref, :process, _, {:shutdown, :authority_changed}}, 1000
  end

  # Counts what the view's process reads of account roles from here on.
  defp watch_role_reads(view) do
    test = self()
    handler = "role-reads-#{System.unique_integer([:positive])}"
    pid = view.pid

    :telemetry.attach(
      handler,
      [:brando_integration, :repo, :query],
      fn _event, _measurements, %{query: query}, _config ->
        if self() == pid and query =~ ~s("users") and query =~ ~s(."role"), do: send(test, {handler, query})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    fn ->
      :sys.get_state(pid)
      flush_role_reads(handler, 0)
    end
  end

  defp flush_role_reads(handler, count) do
    receive do
      {^handler, _query} -> flush_role_reads(handler, count + 1)
    after
      0 -> count
    end
  end

  describe "set_status on a listing" do
    test "leaves the entry alone for a :user, from any listing", c do
      {:ok, view, _} = live(c.user_conn, "/admin/pages")
      render_hook(view, "set_status", %{"id" => c.page.id, "status" => "published", "schema" => to_string(Page)})
      assert status(c.page) == :draft

      {:ok, view, _} = live(c.user_conn, "/admin/assets/images")
      render_hook(view, "set_status", %{"id" => c.page.id, "status" => "published", "schema" => to_string(Page)})
      assert status(c.page) == :draft
    end

    test "works for an editor", c do
      {:ok, view, _} = live(c.editor_conn, "/admin/pages")
      render_hook(view, "set_status", %{"id" => c.page.id, "status" => "published", "schema" => to_string(Page)})
      assert status(c.page) == :published
    end

    test "Status.update_status refuses a :user by itself", c do
      assert {:error, :forbidden} = Brando.Trait.Status.update_status(Page, c.page.id, "published", c.user)
      assert status(c.page) == :draft

      assert Brando.Trait.Status.update_status(Page, c.page.id, "published", c.editor)
      assert status(c.page) == :published
    end

    test "a schema name that names nothing changes nothing and does not crash", c do
      {:ok, view, _} = live(c.editor_conn, "/admin/pages")
      render_hook(view, "set_status", %{"id" => c.page.id, "status" => "published", "schema" => "Elixir.Nothing"})
      assert Process.alive?(view.pid)
      assert status(c.page) == :draft
    end
  end

  describe "the listing's sequenced event, a LiveComponent's" do
    setup c do
      other = Factory.insert(:page, creator: c.owner, title: "Other", uri: "other", sequence: 1)
      %{ids: [other.id, c.page.id]}
    end

    defp list(view), do: with_target(view, cid_of(view, "[data-testid=listing-footer]"))

    defp sequence_of(id), do: Repo.one(from(p in Page, where: p.id == ^id, select: p.sequence))

    test "leaves the order alone for a :user", c do
      before = Enum.map(c.ids, &sequence_of/1)
      {:ok, view, _} = live(c.user_conn, "/admin/pages")

      view |> list() |> render_hook("sequenced", %{"sortable_id" => "content_listing|x", "ids" => c.ids})
      assert Enum.map(c.ids, &sequence_of/1) == before
    end

    test "reorders for an editor", c do
      {:ok, view, _} = live(c.editor_conn, "/admin/pages")

      view |> list() |> render_hook("sequenced", %{"sortable_id" => "content_listing|x", "ids" => c.ids})
      assert Enum.map(c.ids, &sequence_of/1) == [0, 1]
    end

    test "Sequenced.sequence refuses the user given as an option", c do
      before = Enum.map(c.ids, &sequence_of/1)

      assert {:error, :forbidden} = Brando.Trait.Sequenced.sequence(Page, %{"ids" => c.ids}, nil, user: c.user)
      assert Enum.map(c.ids, &sequence_of/1) == before
    end

    test "Sequenced.sequence reads the role stored now", c do
      editor = c.editor
      demote(editor)

      assert {:error, :forbidden} = Brando.Trait.Sequenced.sequence(Page, %{"ids" => c.ids}, nil, user: editor)
    end

    # Module and container code is a superuser's, their order is not.
    test "an editor and an admin reorder modules and containers, a :user does not", c do
      admin = TestUsers.insert_user(role: :admin)

      for schema <- [Brando.Content.Module, Brando.Content.Container] do
        ids = [code_row(schema, "a", 5), code_row(schema, "b", 6)]

        assert {:error, :forbidden} = Brando.Trait.Sequenced.sequence(schema, %{"ids" => ids}, nil, user: c.user)
        assert sequences(schema, ids) == [5, 6]

        for {actor, offset} <- [{c.editor, 10}, {admin, 20}] do
          params = %{"ids" => ids, "sortable_offset" => to_string(offset)}
          refute match?({:error, _}, Brando.Trait.Sequenced.sequence(schema, params, nil, user: actor))
          assert sequences(schema, ids) == [offset, offset + 1]
        end
      end
    end

    test "the listing says the sequence was updated when it was", c do
      Brando.endpoint().subscribe("user:#{c.editor.id}")
      {:ok, view, _} = live(c.editor_conn, "/admin/pages")

      view |> list() |> render_hook("sequenced", %{"sortable_id" => "content_listing|x", "ids" => c.ids})
      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{level: :success}}
    end

    defp code_row(Brando.Content.Module, name, sequence) do
      Factory.insert(:module, name: %{"en" => "#{name}-#{System.unique_integer([:positive])}"}, sequence: sequence).id
    end

    defp code_row(Brando.Content.Container, name, sequence) do
      Repo.insert!(%Brando.Content.Container{
        name: name,
        namespace: "Test",
        code: "<div>{{ content }}</div>",
        sequence: sequence
      }).id
    end

    defp sequences(schema, ids), do: Enum.map(ids, &Repo.get!(schema, &1).sequence)
  end

  describe "the utility screens" do
    @source "Elixir.Brando.Pages.Page.Blocks"

    defp loose_block(description) do
      Repo.insert!(%Block{type: :module, source: @source, uid: Brando.Utils.generate_uid(), description: description})
    end

    test "loose blocks: a :user removes and restores nothing, an editor does", c do
      loose = loose_block("Old hero")
      {:ok, view, _} = live(c.user_conn, "/admin/config/utils/loose-blocks")

      render_click(view, "toggle", %{"id" => to_string(loose.id)})
      render_click(view, "remove", %{})
      assert Repo.get(Block, loose.id)

      {:ok, view, _} = live(c.editor_conn, "/admin/config/utils/loose-blocks")
      render_click(view, "toggle", %{"id" => to_string(loose.id)})
      render_click(view, "remove", %{})
      refute Repo.get(Block, loose.id)

      archive = Repo.one!(from(a in Brando.Content.BlockArchive, where: a.root_block_id == ^loose.id))

      {:ok, view, _} = live(c.user_conn, "/admin/config/utils/loose-blocks")
      render_click(view, "restore", %{"id" => to_string(archive.id)})
      refute Repo.get(Block, loose.id)

      {:ok, view, _} = live(c.editor_conn, "/admin/config/utils/loose-blocks")
      render_click(view, "restore", %{"id" => to_string(archive.id)})
      assert Repo.get(Block, loose.id)
    end

    test "BlockAudit refuses a :user by itself", c do
      loose = loose_block("Old hero")

      assert {:error, :forbidden} = Brando.Content.BlockAudit.remove([loose.id], c.user)
      assert {:error, :forbidden} = Brando.Content.BlockAudit.restore(0, c.user)
      assert Repo.get(Block, loose.id)
    end

    test "scheduled publishing: a :user cancels no revision job, and its flag and history stay", c do
      {job, revision} = scheduled_revision(c)
      {:ok, view, _} = live(c.user_conn, "/admin/config/scheduled_publishing")

      render_click(view, "delete_job", %{"id" => to_string(job.id)})

      assert Repo.get(Oban.Job, job.id)
      assert revision_row(c.page, revision).scheduled
    end

    test "Publisher.delete_job refuses a :user by itself and reads the stored role", c do
      {job, revision} = scheduled_revision(c)

      for actor <- [c.user, demote(c.editor) |> Map.put(:role, :editor)] do
        assert {:error, :forbidden} = Publisher.delete_job(job.id, actor)
      end

      assert Repo.get(Oban.Job, job.id)
      assert revision_row(c.page, revision).scheduled
    end

    test "scheduled publishing: an editor cancels the job", c do
      {job, revision} = scheduled_revision(c)
      {:ok, view, _} = live(c.editor_conn, "/admin/config/scheduled_publishing")

      Oban.Testing.with_testing_mode(:manual, fn ->
        render_click(view, "delete_job", %{"id" => to_string(job.id)})
      end)

      refute Repo.get(Oban.Job, job.id)
      refute revision_row(c.page, revision).scheduled
    end

    test "scheduled publishing: refresh still works for a :user", c do
      {:ok, view, _} = live(c.user_conn, "/admin/config/scheduled_publishing")
      assert render_click(view, "refresh_jobs", %{}) =~ "</"
    end

    test "emptying the caches is refused for a :user, not for an editor", c do
      preserve_query_cache(Page)
      # Another test's tenant keys aren't this screen's: it reads every key.
      Cachex.clear(:query)
      key = {:list, Page.__schema__(:source), "legacy-events-#{System.unique_integer([:positive])}"}
      Brando.Cache.Query.put(key, :held)

      {:ok, view, _} = live(c.user_conn, "/admin/config/cache")
      render_click(view, "empty_caches", %{})
      assert Brando.Cache.Query.get(key) == :held

      {:ok, view, _} = live(c.editor_conn, "/admin/config/cache")
      render_click(view, "empty_caches", %{})
      assert Brando.Cache.Query.get(key) == nil
    end

    test "syncing identifiers is refused for a :user", c do
      Repo.delete_all(Brando.Content.Identifier)
      {:ok, view, _} = live(c.user_conn, "/admin/config/utils")

      render_click(view, "sync_identifiers", %{})
      assert Repo.aggregate(Brando.Content.Identifier, :count) == 0
    end

    test "sorting a library by use moves nothing for a :user", c do
      folder_id = FolderBrowser.folder_id_for("images/site/default")
      image = Factory.insert(:image, folder_id: folder_id, status: :processed)
      block = Repo.insert!(%Block{type: :module, source: @source, uid: Brando.Utils.generate_uid()})
      Repo.insert!(%Page.Blocks{entry_id: c.page.id, block_id: block.id, sequence: 0})
      Factory.insert(:ref, block_id: block.id, image_id: image.id)
      Brando.Content.create_identifier(Page, c.page)

      {:ok, view, _} = live(c.user_conn, "/admin/assets/images?filter:folder_id=#{folder_id}")
      render_click(view, "sweep_open", %{})
      render_click(view, "sweep_apply", %{})

      assert Repo.get!(Image, image.id).folder_id == folder_id
    end

    test "rerender_entry is refused for a :user", c do
      {:ok, view, _} = live(c.user_conn, "/admin/pages")
      before = Repo.get!(Page, c.page.id).updated_at

      render_hook(view, "rerender_entry", %{"id" => c.page.id})
      assert Repo.get!(Page, c.page.id).updated_at == before
    end
  end

  describe "the SEO screen" do
    test "a :user toggles no IndexNow and rejects no suggestion; the tab still changes", c do
      enabled? = Brando.IndexNow.settings().enabled
      suggestion = suggestion(c.page)

      {:ok, view, _} = live(c.user_conn, "/admin/config/seo")
      render_click(view, "toggle_indexnow", %{})
      assert Brando.IndexNow.settings().enabled == enabled?

      render_click(view, "reject_suggestion", %{"id" => suggestion.id})
      assert Repo.get!(Brando.SEO.Suggestion, suggestion.id).status == :pending

      assert render_click(view, "tab", %{"tab" => "content"}) =~ "</"
      assert Process.alive?(view.pid)
    end

    test "Suggestions.reject refuses a :user by itself, not an editor", c do
      suggestion = suggestion(c.page)

      assert {:error, :forbidden} = Brando.SEO.Suggestions.reject(suggestion.id, c.user)
      assert {:ok, %{status: :rejected}} = Brando.SEO.Suggestions.reject(suggestion.id, c.editor)
    end
  end

  describe "an open socket" do
    # `BrandoAdmin.Authorization` ends a view whose role was lowered, and the client
    # rejoins it at the stored role: the event does nothing, and nor does a retry.
    test "an editor demoted after mount does not act on it, nor after the rejoin", c do
      {:ok, view, _} = live(c.editor_conn, "/admin/pages")
      demote(c.editor)

      assert_event_ends_view(view, fn ->
        render_hook(view, "set_status", %{"id" => c.page.id, "status" => "published", "schema" => to_string(Page)})
      end)

      assert status(c.page) == :draft

      {:ok, view, _} = live(c.editor_conn, "/admin/pages")
      render_hook(view, "set_status", %{"id" => c.page.id, "status" => "published", "schema" => to_string(Page)})
      assert status(c.page) == :draft
      assert Process.alive?(view.pid)
    end

    test "a :user promoted after mount writes on it, at the role read for the event", c do
      {:ok, view, _} = live(c.user_conn, "/admin/pages")
      Repo.update!(Ecto.Changeset.change(c.user, role: :editor))

      render_hook(view, "set_status", %{"id" => c.page.id, "status" => "published", "schema" => to_string(Page)})
      assert status(c.page) == :published
    end

    test "a refused event reads the role once", c do
      {:ok, view, _} = live(c.user_conn, "/admin/pages")
      reads = watch_role_reads(view)

      render_hook(view, "set_status", %{"id" => c.page.id, "status" => "published", "schema" => to_string(Page)})
      assert status(c.page) == :draft
      assert reads.() == 1
    end

    test "a read-only event is let through: a :user's filter works", c do
      {:ok, view, _} = live(c.user_conn, "/admin/pages")
      assert Process.alive?(view.pid)
      assert view |> list() |> render_click("next_filter_key", %{}) =~ "</"
    end
  end

  describe "a block field on an open socket" do
    setup do
      %{identity: identity} = Brando.ProposalFixtures.context()
      %{identity: identity, uids: identity |> Editors.rows() |> Enum.map(& &1.block.uid)}
    end

    test "an editor demoted since sends no block edit, and the other editor's save does not store it", c do
      [first | _] = c.uids
      owner_conn = log_in_user(Phoenix.ConnTest.build_conn(), c.owner)
      demoted = open_blocks(c.editor_conn, c.identity)
      other = open_blocks(owner_conn, c.identity)

      Editors.type(demoted, first, "<p>While an editor</p>")
      Editors.await(fn -> Editors.shown_text(other, first) == "<p>While an editor</p>" end)

      demote(c.editor)
      Editors.type(demoted, first, "<p>Injected</p>")
      :timer.sleep(100)
      assert Editors.shown_text(other, first) == "<p>While an editor</p>"

      session = EditSession.whereis(EditSession.ref(Page, c.identity.id, c.identity.language))
      assert :sys.get_state(session).clients[demoted.pid].read_only

      other |> form("#page_form_form") |> render_submit()
      assert_push_event(other, "b:submit", %{}, 2_000)
      other |> form("#page_form_form") |> render_submit()
      assert_redirect(other, 3_000)

      refute inspect(Editors.rows(c.identity)) =~ "Injected"
    end

    test "with groups, two members' block edits still reach each other", c do
      with_groups()
      [first | _] = c.uids
      owner_conn = log_in_user(Phoenix.ConnTest.build_conn(), c.owner)
      a = open_blocks(c.editor_conn, c.identity)
      b = open_blocks(owner_conn, c.identity)

      Editors.type(a, first, "<p>Together</p>")
      Editors.await(fn -> Editors.shown_text(b, first) == "<p>Together</p>" end)
    end
  end

  describe "presence from a block" do
    setup do
      %{identity: identity} = Brando.ProposalFixtures.context()
      [%{block: %{uid: uid}} | _] = Editors.rows(identity)
      %{identity: identity, uid: uid}
    end

    defp block_target(view, uid), do: with_target(view, cid_of(view, "#entry_block_form-#{uid}"))

    defp block_assign(view, key), do: :sys.get_state(view.pid).socket.assigns[key]

    defp watch_blocks(page) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("block_presence", Page, page.id))
    end

    defp someone_joined(page) do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        Brando.Tenant.Topic.entry("field_sync", Page, page.id),
        {:editor_joined, %{user_id: -1, tab: "someone", part: :blocks}}
      )
    end

    test "the focus event: nothing from a :user, the lock from an editor", c do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("active_field", Page, c.identity.id))
      user_id = c.user.id
      editor_id = c.editor.id

      view = open_blocks(c.user_conn, c.identity)
      view |> block_target(c.uid) |> render_hook("focus", %{"field" => "field-from-user"})
      refute_receive {:active_field, "field-from-user", ^user_id, _}, 100

      view = open_blocks(c.editor_conn, c.identity)
      view |> block_target(c.uid) |> render_hook("focus", %{"field" => "field-from-editor"})
      assert_receive {:active_field, "field-from-editor", ^editor_id, _}
    end

    test "focus and the answer to a joiner send nothing for a :user, and it still works locally", c do
      watch_blocks(c.identity)
      view = open_blocks(c.user_conn, c.identity)

      render_hook(view, "block_focused", %{"uid" => c.uid, "field" => "f", "label" => "L"})
      assert block_assign(view, :current_focused_block_uid) == c.uid
      refute_receive {:block_focus, %{uid: _}}, 100

      someone_joined(c.identity)
      refute_receive {:block_focus, %{uid: _}}, 100

      render_hook(view, "block_blurred", %{"uid" => c.uid, "still_inside" => false})
      assert block_assign(view, :current_focused_block_uid) == nil
    end

    test "an editor demoted in a block enters no other: the view ends", c do
      watch_blocks(c.identity)
      uid = c.uid
      view = open_blocks(c.editor_conn, c.identity)

      render_hook(view, "block_focused", %{"uid" => uid, "field" => "f", "label" => "L"})
      assert_receive {:block_focus, %{uid: ^uid}}

      demote(c.editor)

      assert_event_ends_view(view, fn ->
        render_hook(view, "block_focused", %{"uid" => "another", "field" => "f", "label" => "L"})
      end)

      refute_receive {:block_focus, %{uid: "another"}}, 100
    end

    test "an editor's focus, blur and answer to a joiner reach the others", c do
      watch_blocks(c.identity)
      uid = c.uid
      id = c.editor.id
      view = open_blocks(c.editor_conn, c.identity)

      render_hook(view, "block_focused", %{"uid" => uid, "field" => "f", "label" => "L"})
      assert_receive {:block_focus, %{uid: ^uid, user_id: ^id}}

      someone_joined(c.identity)
      assert_receive {:block_focus, %{uid: ^uid, user_id: ^id}}

      render_hook(view, "block_blurred", %{"uid" => uid, "still_inside" => false})
      assert_receive {:block_blur, %{uid: ^uid, user_id: ^id}}
    end

    test "with groups, a member who may update still sends them", c do
      with_groups()
      watch_blocks(c.identity)
      uid = c.uid
      view = open_blocks(c.editor_conn, c.identity)

      render_hook(view, "block_focused", %{"uid" => uid, "field" => "f", "label" => "L"})
      assert_receive {:block_focus, %{uid: ^uid}}
    end
  end

  defmodule MultiSelectHost do
    use Phoenix.LiveView, layout: false

    def mount(_, %{"user_id" => user_id}, socket) do
      var = %Brando.Content.Var{id: 4711, link_identifier_schemas: []}
      form = Phoenix.Component.to_form(Ecto.Changeset.change(var), as: "var")
      user = Brando.Repo.get!(Brando.Users.User, user_id)
      {:ok, Phoenix.Component.assign(socket, form: form, current_user: user)}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={BrandoAdmin.Components.Form.Input.MultiSelect}
        id="schemas"
        field={@form[:link_identifier_schemas]}
        label="Schemas"
        current_user={@current_user}
        opts={[options: [%{label: "Contact", value: "contact"}]]}
      />
      """
    end
  end

  describe "a multi-select's options" do
    setup do
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("active_field", Brando.Content.Var, 4711))
    end

    defp toggle_options(conn, user) do
      {:ok, view, _html} = live_isolated(conn, MultiSelectHost, session: %{"user_id" => user.id})
      view |> element(".multiselect > .button-edit") |> render_click()
      view
    end

    test "lock nothing for a :user, and still open", c do
      id = c.user.id

      view = toggle_options(c.user_conn, c.user)
      assert has_element?(view, "button", ~r/^\s*OK\s*$/)
      refute_receive {:active_field, _, ^id, _}, 100
    end

    test "lock the field for an editor", c do
      id = c.editor.id

      toggle_options(c.editor_conn, c.editor)
      assert_receive {:active_field, "var[link_identifier_schemas]", ^id, _}
    end
  end

  describe "the revisions drawer" do
    setup c do
      {:ok, _} = Revisions.create_revision(c.page, c.owner, false)
      {:ok, keep} = Revisions.create_revision(c.page, c.owner, false)
      {:ok, other} = Revisions.create_revision(c.page, c.owner, false)
      Revisions.protect_revision(Page, c.page.id, keep.revision, true, :system)

      %{protected: keep.revision, unprotected: other.revision}
    end

    defp drawer(conn, page) do
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      with_target(view, cid_of(view, "#page_form-revisions-drawer"))
    end

    test "a :user deletes, purges, protects and unprotects nothing", c do
      drawer = drawer(c.user_conn, c.page)
      before = revisions(c.page)

      render_click(drawer, "delete_revision", %{"value" => to_string(c.unprotected)})
      render_click(drawer, "purge_inactive_revisions", %{})
      render_click(drawer, "unprotect_revision", %{"value" => to_string(c.protected)})
      render_click(drawer, "protect_revision", %{"value" => to_string(c.unprotected)})

      assert revisions(c.page) == before
    end

    test "an editor still deletes and protects", c do
      drawer = drawer(c.editor_conn, c.page)

      render_click(drawer, "protect_revision", %{"value" => to_string(c.unprotected)})
      assert revision_row(c.page, c.unprotected).protected

      render_click(drawer, "unprotect_revision", %{"value" => to_string(c.unprotected)})
      render_click(drawer, "delete_revision", %{"value" => to_string(c.unprotected)})
      refute revision_row(c.page, c.unprotected)
    end

    test "a :user still reads the history", c do
      {view, _html} = live_form(c.user_conn, "/admin/pages/update/#{c.page.id}")
      drawer = with_target(view, cid_of(view, "#page_form-revisions-drawer"))

      view |> with_target(cid_of(view, "#page_form-el")) |> render_click("toggle_revisions_drawer_status", %{})
      render_click(drawer, "tab", %{"tab" => "revisions"})
      assert render_async(view) =~ "revision-line-"
    end

    test "the contexts refuse a :user by themselves, and read the stored role", c do
      editor = c.editor
      demote(editor)

      for actor <- [c.user, editor] do
        assert {0, _} = Revisions.delete_revision(Page, c.page.id, c.unprotected, actor)
        assert {0, _} = Revisions.purge_revisions(Page, c.page.id, actor)
        assert {0, _} = Revisions.protect_revision(Page, c.page.id, c.protected, false, actor)
      end

      assert revision_row(c.page, c.unprotected)
      assert revision_row(c.page, c.protected).protected
    end

    test "a :user cancels no scheduled revision, an editor does", c do
      {_job, revision} = scheduled_revision(c)

      assert {:error, :forbidden} = Publisher.cancel_scheduled_revision(Page, c.page.id, revision, c.user)
      assert revision_row(c.page, revision).scheduled

      assert :ok =
               Oban.Testing.with_testing_mode(:manual, fn ->
                 Publisher.cancel_scheduled_revision(Page, c.page.id, revision, c.editor)
               end)

      refute revision_row(c.page, revision).scheduled
    end

    test "the drawer's cancel event leaves the schedule for a :user", c do
      {job, revision} = scheduled_revision(c)
      drawer = drawer(c.user_conn, c.page)

      render_click(drawer, "cancel_scheduled_revision", %{"value" => to_string(revision)})

      assert Repo.get(Oban.Job, job.id)
      assert revision_row(c.page, revision).scheduled
    end
  end

  describe "notes" do
    test "a :user adds, replies to, resolves and reopens nothing", c do
      {:ok, thread, _} = Brando.Notes.create_thread(Page, c.page.id, c.editor, %{"body" => "Look"})

      assert {:error, :forbidden} = Brando.Notes.create_thread(Page, c.page.id, c.user, %{"body" => "Mine"})
      assert {:error, :forbidden} = Brando.Notes.reply(thread, c.user, %{"body" => "Mine"})
      assert {:error, :forbidden} = Brando.Notes.resolve(thread, c.user)

      {:ok, thread} = Brando.Notes.resolve(thread, c.editor)
      assert {:error, :forbidden} = Brando.Notes.reopen(thread, c.user)

      assert [%{id: id}] = Brando.Notes.list_threads(Page, c.page.id)
      assert id == thread.id
    end

    test "can_write? follows the role stored now, and an editor still can", c do
      assert Brando.Notes.can_write?(c.editor, c.page)
      refute Brando.Notes.can_write?(c.user, c.page)

      editor = c.editor
      demote(editor)
      refute Brando.Notes.can_write?(editor, c.page)
    end
  end

  describe "an entry form's field sync" do
    defp form(view), do: with_target(view, cid_of(view, "#page_form-el"))

    defp edit(view, field, value) do
      view |> form() |> render_hook("focus", %{"field" => "page[#{field}]"})

      params =
        view
        |> render()
        |> form_params("#page_form_form")
        |> put_in(["page", field], value)
        |> Map.put("_target", ["page", field])

      view |> element("#page_form_form") |> render_change(params)
      view |> form() |> render_hook("blur", %{"field" => "page[#{field}]"})
    end

    defp shown(view, field), do: view |> render() |> form_params("#page_form_form") |> get_in(["page", field])

    defp await_shown(view, field, value, tries \\ 50) do
      cond do
        shown(view, field) == value -> true
        tries == 0 -> false
        true -> :timer.sleep(20) && await_shown(view, field, value, tries - 1)
      end
    end

    test "a :user's edit reaches no open form, and the editor's save does not store it", c do
      {editor, _} = live_form(c.editor_conn, "/admin/pages/update/#{c.page.id}")
      {user, _} = live_form(c.user_conn, "/admin/pages/update/#{c.page.id}")

      edit(user, "title", "Injected")
      :timer.sleep(100)
      assert shown(user, "title") == "Injected"
      assert shown(editor, "title") == "Om oss"

      editor |> form() |> render_hook("save_redirect_target", %{})
      editor |> element("#page_form_form") |> render_submit()
      assert_push_event(editor, "b:submit", %{}, 5_000)
      editor |> element("#page_form_form") |> render_submit()
      assert Repo.get!(Page, c.page.id).title == "Om oss"
    end

    test "nor a form opened afterwards", c do
      {user, _} = live_form(c.user_conn, "/admin/pages/update/#{c.page.id}")
      edit(user, "title", "Injected")

      {editor, _} = live_form(c.editor_conn, "/admin/pages/update/#{c.page.id}")
      :timer.sleep(100)
      assert shown(editor, "title") == "Om oss"
    end

    test "a :user's form still follows an editor's", c do
      {user, _} = live_form(c.user_conn, "/admin/pages/update/#{c.page.id}")
      {editor, _} = live_form(c.editor_conn, "/admin/pages/update/#{c.page.id}")

      edit(editor, "title", "From the editor")
      assert await_shown(user, "title", "From the editor")
    end

    test "two editors still sync", c do
      other = log_in_user(Phoenix.ConnTest.build_conn(), c.owner)
      {a, _} = live_form(c.editor_conn, "/admin/pages/update/#{c.page.id}")
      {b, _} = live_form(other, "/admin/pages/update/#{c.page.id}")

      edit(a, "title", "Together")
      assert await_shown(b, "title", "Together")
    end

    test "a field locked before a demotion is released after it", c do
      {view, _} = live_form(c.editor_conn, "/admin/pages/update/#{c.page.id}")
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.entry("active_field", Page, c.page.id))

      view |> form() |> render_hook("focus", %{"field" => "page[title]"})
      assert_receive {:active_field, "page[title]", _, _}, 1_000

      demote(c.editor)
      view |> form() |> render_hook("blur", %{"field" => "page[title]"})
      assert_receive {:active_field, nil, _, _}, 1_000
    end

    test "a form drops a message claiming to come from a :user", c do
      {editor, _} = live_form(c.editor_conn, "/admin/pages/update/#{c.page.id}")

      forged =
        {:fields_shipped,
         %{
           changes: [%{field: :title, value: "Forged", assoc?: false, clock: {1000, "someone"}}],
           clocks: nil,
           user_id: c.user.id,
           tab: "someone",
           to: nil
         }}

      Phoenix.PubSub.broadcast(Brando.pubsub(), Brando.Tenant.Topic.entry("field_sync", Page, c.page.id), forged)
      :timer.sleep(100)
      assert shown(editor, "title") == "Om oss"
    end
  end

  describe "what a :user keeps" do
    test "reads listings and opens forms", c do
      {:ok, _, html} = live(c.user_conn, "/admin/pages")
      assert html =~ "Om oss"
      {_view, html} = live_form(c.user_conn, "/admin/pages/update/#{c.page.id}")
      assert html =~ "Om oss"
    end

    test "changes its own profile", c do
      {view, _} = live_form(c.user_conn, "/admin/users/update/#{c.user.id}", "user_form")

      params = view |> render() |> form_params("#user_form_form") |> put_in(["user", "name"], "Renamed")
      view |> element("#user_form_form") |> render_change(params)
      view |> with_target(cid_of(view, "#user_form-el")) |> render_hook("save_redirect_target", %{})
      view |> element("#user_form_form") |> render_submit(params)

      assert Repo.get!(Brando.Users.User, c.user.id).name == "Renamed"
    end

    test "changes no other account", c do
      assert {:error, :forbidden} =
               Boundary.change(c.user, :update, Ecto.Changeset.change(c.editor, name: "Renamed"))
    end
  end

  describe "with groups" do
    setup c do
      with_groups()
      %{owner_conn: log_in_user(Phoenix.ConnTest.build_conn(), c.owner)}
    end

    test "the legacy role makes no account read-only", c do
      refute Boundary.read_only_account?(c.user)
    end

    test "members who may update still set a status and sync fields", c do
      {:ok, view, _} = live(c.editor_conn, "/admin/pages")
      render_hook(view, "set_status", %{"id" => c.page.id, "status" => "published", "schema" => to_string(Page)})
      assert status(c.page) == :published

      {a, _} = live_form(c.editor_conn, "/admin/pages/update/#{c.page.id}")
      {b, _} = live_form(c.owner_conn, "/admin/pages/update/#{c.page.id}")

      edit(a, "title", "Together")
      assert await_shown(b, "title", "Together")
    end

    test "revisions and notes answer by the groups, for the member's own actor", c do
      {:ok, revision} = Revisions.create_revision(c.page, c.owner, false)

      assert {1, _} = Revisions.protect_revision(Page, c.page.id, revision.revision, true, c.editor)
      assert {0, _} = Revisions.protect_revision(Page, c.page.id, revision.revision, false, c.user)
      assert revision_row(c.page, revision.revision).protected

      assert Brando.Notes.can_write?(c.editor, c.page)
      refute Brando.Notes.can_write?(c.user, c.page)
    end

    # Field sync's check asks about the schema and the record check would pass
    # their own profile, but the form does not open for them: nothing to sync.
    test "a member who may update only their own profile does not open the user form", c do
      grant(c, ~w(brando.admin.access brando.profile.read brando.profile.update))

      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(c.user_conn, "/admin/users/update/#{c.user.id}")
    end

    test "a refused reorder is not reported as done", c do
      other = Factory.insert(:page, creator: c.owner, title: "Other", uri: "other", sequence: 1)
      ids = [other.id, c.page.id]
      before = Enum.map(ids, &sequence_of/1)
      grant(c, ~w(brando.admin.access brando.pages.read))
      Brando.endpoint().subscribe("user:#{c.user.id}")
      {:ok, view, _} = live(c.user_conn, "/admin/pages")

      view |> list() |> render_hook("sequenced", %{"sortable_id" => "content_listing|x", "ids" => ids})

      assert Enum.map(ids, &sequence_of/1) == before
      refute_receive %Phoenix.Socket.Broadcast{event: "toast"}, 100
    end
  end

  describe "refusals a :user can meet in ordinary use" do
    test "saving another's entry stores nothing and keeps the form open", c do
      {view, _} = live_form(c.user_conn, "/admin/pages/update/#{c.page.id}")
      edit(view, "title", "Mine")

      view |> form() |> render_hook("save_redirect_target", %{})
      view |> element("#page_form_form") |> render_submit()
      view |> element("#page_form_form") |> render_submit()

      # The blocks arrive and the save runs after the submit returns: render
      # again so a refusal that crashed the form fails here, not later.
      _ = render(view)
      _ = render(view)

      assert Process.alive?(view.pid)
      assert Repo.get!(Page, c.page.id).title == "Om oss"
    end

    test "a refused save from the editing tab stores nothing and keeps the form open", c do
      # The tab that edits sends its save to the context, which refuses the
      # account; the blocks arrive first, so the save runs after the submit.
      params = %{"brando_tab" => "refused-save", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}

      {view, _} =
        c.user_conn |> Phoenix.LiveViewTest.put_connect_params(params) |> live_form("/admin/pages/update/#{c.page.id}")

      await_editing_tab(view)

      edit(view, "title", "Mine")
      view |> form() |> render_hook("save_redirect_target", %{})
      %{proxy: {ref, _topic, _}} = view

      # Saving is two submits: the first collects the block fields, the
      # second reaches the context.
      view |> element("#page_form_form") |> render_submit()
      assert_receive {^ref, {:push_event, "b:submit", _}}, 2_000
      view |> element("#page_form_form") |> render_submit()

      await_saved_or_refused(view)
      assert Process.alive?(view.pid)
      assert Repo.get!(Page, c.page.id).title == "Om oss"
    end

    test "closing an image drawer it may only look at closes it", c do
      {view, _} = live_form(c.user_conn, "/admin/pages/update/#{c.page.id}")

      view |> form() |> render_hook("save_image", %{})
      assert Process.alive?(view.pid)
    end

    test "a private saved view stays its own; a shared one is refused", c do
      params = %{"name" => "Mine", "params" => %{}}

      assert {:ok, view} = Brando.ListingViews.create_view(c.user, Page, :default, Map.put(params, "shared", false))

      assert {:error, :forbidden} =
               Brando.ListingViews.create_view(c.user, Page, :default, Map.put(params, "shared", true))

      assert {:error, :forbidden} = Brando.ListingViews.update_view(c.user, view, %{"shared" => true})
      assert {:ok, _} = Brando.ListingViews.create_view(c.editor, Page, :default, Map.put(params, "shared", true))
    end
  end

  describe "saved views, for an account demoted since" do
    defp saved_view(user, shared) do
      attrs = %{"name" => "View #{System.unique_integer([:positive])}", "params" => %{}, "shared" => shared}
      {:ok, view} = ListingViews.create_view(user, Page, :default, attrs)
      view
    end

    test "moderating follows the stored role, not the mounted one", c do
      admin = TestUsers.insert_user(role: :admin)
      assert ListingViews.moderator?(admin)
      demote(admin)
      refute ListingViews.moderator?(admin)

      shared = saved_view(c.editor, true)
      assert {:error, :forbidden} = ListingViews.update_view(admin, shared, %{"name" => "Renamed"})
      assert {:error, :forbidden} = ListingViews.delete_view(admin, shared)

      editor = c.editor
      Repo.update!(Ecto.Changeset.change(editor, role: :admin))
      assert ListingViews.moderator?(editor)
    end

    test "their own shared view is one others see: not renamed, updated or deleted" do
      admin = TestUsers.insert_user(role: :admin)
      shared = saved_view(admin, true)
      demote(admin)

      refute ListingViews.can_manage?(admin, shared)
      assert {:error, :forbidden} = ListingViews.update_view(admin, shared, %{"name" => "Renamed"})
      assert {:error, :forbidden} = ListingViews.delete_view(admin, shared)
      assert Repo.get!(ListingViews.View, shared.id).name == shared.name
    end

    test "a shared view transferred to a :user stays the moderators', its private one stays behind", c do
      admin = TestUsers.insert_user(role: :admin)
      leaving = TestUsers.insert_user(role: :editor)
      shared = saved_view(leaving, true)
      private = saved_view(leaving, false)

      assert {:ok, _} = Brando.Users.transfer_user_content(leaving.id, c.user.id)

      assert %{creator_id: to_id} = Repo.get!(ListingViews.View, shared.id)
      assert to_id == c.user.id
      assert Repo.get!(ListingViews.View, private.id).creator_id == leaving.id

      refute ListingViews.can_manage?(c.user, Repo.get!(ListingViews.View, shared.id))
      assert ListingViews.can_manage?(admin, Repo.get!(ListingViews.View, shared.id))
    end

    test "their own private view stays theirs", c do
      for user <- [c.user, demote(c.editor)] do
        private = saved_view(user, false)
        assert ListingViews.can_manage?(user, private)
        assert {:ok, %{name: "Renamed"}} = ListingViews.update_view(user, private, %{"name" => "Renamed"})
        assert {:ok, _} = ListingViews.delete_view(user, private)
      end
    end

    test "an editor and an admin keep their own shared views, an admin the others' too", c do
      admin = TestUsers.insert_user(role: :admin)
      own = saved_view(c.editor, true)

      assert {:ok, %{name: "Renamed"}} = ListingViews.update_view(c.editor, own, %{"name" => "Renamed"})
      assert {:ok, %{name: "Moderated"}} = ListingViews.update_view(admin, own, %{"name" => "Moderated"})
      assert {:ok, _} = ListingViews.delete_view(c.editor, own)
    end

    test "with groups, nothing changes for their own shared view", c do
      own = saved_view(c.editor, true)
      with_groups()

      assert ListingViews.can_manage?(c.editor, own)
      assert {:ok, _} = ListingViews.delete_view(c.editor, own)
    end
  end

  defp with_groups do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    {:ok, _} = Brando.Authorization.Migration.run()
    on_exit(fn -> Boundary.put_scope(nil) end)
  end

  defp grant(c, keys) do
    scope = Brando.Authorization.Scope.standalone(c.owner)
    {:ok, group} = Brando.Authorization.Groups.create(scope, %{name: "Only these"}, keys)
    {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, group.id, c.user.id)
  end

  defp open_blocks(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  defp scheduled_revision(c) do
    {:ok, revision} = Revisions.create_revision(c.page, c.owner, false)
    publish_at = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()

    {:ok, job} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Publisher.schedule_revision(Page, c.page.id, revision.revision, publish_at, c.owner)
      end)

    {job, revision.revision}
  end

  defp revisions(page) do
    entry_type = to_string(Page)

    Repo.all(
      from(r in Revision,
        where: r.entry_type == ^entry_type and r.entry_id == ^page.id,
        order_by: r.revision,
        select: {r.revision, r.protected, r.scheduled}
      )
    )
  end

  defp revision_row(page, number) do
    Repo.get_by(Revision, entry_type: to_string(Page), entry_id: page.id, revision: number)
  end

  defp suggestion(page) do
    Repo.insert!(%Brando.SEO.Suggestion{
      schema: to_string(Page),
      entry_id: page.id,
      field: :meta_description,
      language: "en",
      text: "Suggested",
      status: :pending
    })
  end
end
