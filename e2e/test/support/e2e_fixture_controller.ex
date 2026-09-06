defmodule E2EFixtureController do
  use E2eProjectWeb, :controller

  def login(conn, %{"email" => email}) do
    user = Brando.Users.get_user!(%{matches: %{email: email}})

    conn
    |> login_user(user)
    |> send_resp(200, "")
  end

  def setup(conn, %{"name" => scenario_name}) do
    # Extract the metadata from the user agent
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [beam | _] ->
        # Allow this process to use the associated transaction
        Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
    end

    # Build the scenario
    scenario =
      case scenario_name do
        "admin-user" -> get_admin_user()
      end

    # Log the user in
    conn
    |> login_user(scenario)
    |> send_resp(200, "")
  end

  def authorization(conn, %{"role" => role}) when role in ["reader", "author", "publisher", "none"] do
    [beam | _] = Plug.Conn.get_req_header(conn, "user-agent")
    Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
    owner = get_admin_user()
    user = Brando.Users.get_user!(%{matches: %{email: "editor@brandocms.com"}})
    alias Brando.Authorization.{Groups, Scope}

    for scope <- [Scope.installation(owner), Scope.standalone(owner)] do
      {:ok, groups} = Groups.list(scope)
      for group <- groups, do: Groups.remove_member(scope, group.id, user.id)
    end

    base =
      ~w(brando.admin.access brando.profile.read brando.profile.update brando.pages.read brando.files.read brando.images.read)

    keys =
      case role do
        "reader" ->
          base

        "author" ->
          base ++
            ~w(brando.pages.create brando.pages.update brando.pages.duplicate brando.pages.reorder brando.content_modules.read brando.content_module_sets.read brando.content_palettes.read brando.content_containers.read brando.content_table_templates.read)

        "publisher" ->
          base ++ ~w(brando.pages.update brando.pages.publish brando.pages.schedule)

        "none" ->
          []
      end

    {:ok, group} = Groups.create(Scope.standalone(owner), %{name: "Test #{role}"}, keys)
    {:ok, :ok} = Groups.add_member(Scope.standalone(owner), group.id, user.id)
    json(conn, %{user_id: user.id})
  end

  def get_admin_user do
    Brando.Users.get_user!(%{matches: %{email: "admin@brandocms.com"}})
  end

  # Only routed in the sandbox application. Browser tests use the real editor
  # for capture/restore; this injects failures that an editor cannot create.
  def drafts(conn, %{"action" => "media-state", "schema" => type, "entry_id" => id}) do
    [beam | _] = Plug.Conn.get_req_header(conn, "user-agent")
    Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)

    schema =
      case type do
        "project" -> E2eProject.Projects.Project
        "page" -> Brando.Pages.Page
      end

    entry_id = if id == "new", do: nil, else: String.to_integer(id)

    entry =
      if entry_id do
        {:ok, entry} = Brando.Blueprint.EntryQuery.get(schema, entry_id)
        Brando.Drafts.Params.snapshot(entry)
      end

    user = get_admin_user()
    Brando.Authorization.Boundary.put_scope(Brando.Authorization.Scope.current(user))
    drafts = schema |> Brando.Drafts.identity(entry_id, user.id) |> Brando.Drafts.list()

    counts =
      Map.new(
        [
          images: Brando.Images.Image,
          files: Brando.Files.File,
          videos: Brando.Videos.Video,
          galleries: Brando.Galleries.Gallery
        ],
        fn {key, schema} -> {key, Brando.Repo.aggregate(schema, :count)} end
      )

    json(conn, %{entry: entry, drafts: Enum.map(drafts, & &1.payload), counts: counts})
  end

  def drafts(conn, %{"action" => action}) do
    [beam | _] = Plug.Conn.get_req_header(conn, "user-agent")
    Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
    user = get_admin_user()
    Brando.Authorization.Boundary.put_scope(Brando.Authorization.Scope.current(user))
    identity = Brando.Drafts.identity(Brando.Pages.Page, nil, user.id)
    [draft | _] = Brando.Drafts.list(identity)

    case action do
      "unsupported" ->
        draft |> Ecto.Changeset.change(format_version: 999) |> Brando.Repo.update!()

      "change-module" ->
        [row | _] = draft.payload["blocks"]["blocks"]
        {:ok, _} = Brando.Content.update_module(row["block"]["module_id"], %{refs: [], vars: []}, user)
    end

    json(conn, %{ok: true})
  end

  def login_user(conn, user) do
    token = Brando.Users.generate_user_session_token(user)

    conn
    |> Plug.Conn.fetch_session()
    |> Plug.Conn.put_session(:user_token, token)
    |> Plug.Conn.put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end
end
