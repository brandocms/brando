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
        "media-upload" -> create_media_upload_module()
      end

    # Log the user in
    conn
    |> login_user(scenario)
    |> send_resp(200, "")
  end

  defp create_media_upload_module do
    user = get_admin_user()

    module =
      Brando.Repo.insert!(%Brando.Content.Module{
        type: :liquid,
        uid: Ecto.UUID.generate(),
        name: %{"en" => "Media attachment", "no" => "Medievedlegg"},
        namespace: %{"en" => "05 LIVE PREVIEW TEST", "no" => "05 LIVE PREVIEW TEST"},
        help_text: %{"en" => "File reference and gallery variable", "no" => "Filreferanse og gallerivariabel"},
        class: "media-attachment",
        multi: false,
        datasource: false,
        code: "{% ref refs.attachment %}",
        refs: [
          %Brando.Content.Ref{
            name: "attachment",
            description: "Download attachment",
            uid: Brando.Utils.generate_uid(),
            data: %Brando.Villain.Blocks.FileBlock{type: "file", data: %Brando.Villain.Blocks.FileBlock.Data{}}
          }
        ],
        vars: [
          %Brando.Content.Var{
            type: :gallery,
            key: "media_collection",
            label: "Media collection",
            width: :full,
            placement: :content,
            gallery_allowed_types: [:image, :video],
            creator_id: user.id
          }
        ]
      })

    Brando.Cache.Query.evict_schema(Brando.Content.Module)
    Brando.Content.fetch_module(module.id)
    user
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

  def user_directory(conn, %{"action" => "create"}) do
    [beam | _] = Plug.Conn.get_req_header(conn, "user-agent")
    Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
    {name, avatar} = create_directory_avatar()

    user = get_admin_user()

    user
    |> Ecto.Changeset.change(
      avatar_id: avatar.id,
      last_seen: ~N[2026-09-07 12:34:00],
      last_login: ~N[2026-09-06 08:15:00]
    )
    |> Brando.Repo.update!()
    |> Brando.Cache.Query.evict()

    # Presence fetches run outside the request's SQL sandbox. Populate its user
    # queries here so both editors see the avatar created in this transaction.
    editor = Brando.Users.get_user!(%{matches: %{email: "editor@brandocms.com"}})
    ids = [to_string(user.id), to_string(editor.id)]
    Brando.Users.get_users_map([to_string(user.id)])
    Brando.Users.get_users_map(ids)
    Brando.Users.get_users_map(Enum.reverse(ids))

    json(conn, %{name: name})
  end

  def user_directory(conn, %{"action" => "cleanup", "name" => name}) do
    Brando.Cache.Query.evict_schema(Brando.Users.User)

    if Regex.match?(~r/^e2e-directory-\d+\.jpg$/, name) do
      File.rm(Path.join([Brando.config(:media_path), "images", name]))
    end

    json(conn, %{ok: true})
  end

  def image_creator(conn, %{"image_id" => image_id}) do
    [beam | _] = Plug.Conn.get_req_header(conn, "user-agent")
    Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
    {name, avatar} = create_directory_avatar()

    # Keep the active user's row unlocked: presence records their departure on
    # reload outside the test transaction. Use a separate image contributor.
    creator =
      Brando.Repo.insert!(%Brando.Users.User{
        name: "Image contributor",
        email: name <> "@brandocms.com",
        avatar_id: avatar.id
      })

    Brando.Repo.get!(Brando.Images.Image, image_id)
    |> Ecto.Changeset.change(creator_id: creator.id)
    |> Brando.Repo.update!()

    json(conn, %{name: name})
  end

  def dashboard_access(conn, %{"mode" => mode}) when mode in ["author", "reader", "backend"] do
    [beam | _] = Plug.Conn.get_req_header(conn, "user-agent")
    Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
    alias Brando.Authorization.{Groups, Scope}
    owner = get_admin_user()
    user = Brando.Users.get_user!(%{matches: %{email: "editor@brandocms.com"}})
    scope = Scope.standalone(owner)
    {:ok, groups} = Groups.list(scope)
    existing = Enum.find(groups, &(&1.name == "Dashboard browser access"))

    keys =
      case mode do
        "author" -> ~w(brando.admin.access brando.pages.read brando.pages.update)
        "reader" -> ~w(brando.admin.access brando.pages.read)
        "backend" -> ~w(brando.admin.access)
      end

    if existing do
      {:ok, _} = Groups.update(scope, existing.id, %{name: existing.name}, keys, existing.lock_version)
    else
      for actor_scope <- [scope, Scope.installation(owner)] do
        {:ok, prior_groups} = Groups.list(actor_scope)
        for group <- prior_groups, do: Groups.remove_member(actor_scope, group.id, user.id)
      end

      {:ok, group} = Groups.create(scope, %{name: "Dashboard browser access"}, keys)
      {:ok, :ok} = Groups.add_member(scope, group.id, user.id)
    end

    json(conn, %{ok: true})
  end

  def admin_workspaces(conn, _params) do
    [beam | _] = Plug.Conn.get_req_header(conn, "user-agent")
    Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
    owner = get_admin_user()
    alias BrandoAdmin.Images.FolderBrowser
    {:ok, cfg} = Brando.Videos.get_config_for(%{config_target: "default"})
    scope = FolderBrowser.scope_for(cfg.upload_path)
    {:ok, _} = FolderBrowser.create_folder("Campaigns", scope)
    folder_id = FolderBrowser.folder_id_for("Campaigns", scope)

    for {title, folder} <- [{"Launch%20film.mp4", nil}, {"Studio tour", nil}, {"Campaign film", folder_id}] do
      Brando.Repo.insert!(%Brando.Videos.Video{
        title: title,
        type: :external_file,
        source_url: "https://example.com/Launch%20film.mp4?signature=private-query",
        width: 1920,
        height: 1080,
        duration: "00:31",
        config_target: "default",
        creator_id: owner.id,
        folder_id: folder
      })
    end

    for {title, status} <- [{"Summer collection", :published}, {"Studio notes", :draft}] do
      page =
        Brando.Repo.insert!(%Brando.Pages.Page{
          title: title,
          uri: String.downcase(String.replace(title, " ", "-")),
          language: :en,
          status: status,
          creator_id: owner.id
        })

      Brando.Repo.insert!(%Brando.Content.Identifier{
        schema: Brando.Pages.Page,
        entry_id: page.id,
        title: title,
        status: status,
        language: :en,
        updated_at: DateTime.utc_now(:second)
      })
    end

    json(conn, %{folder_id: folder_id})
  end

  defp create_directory_avatar do
    name = "e2e-directory-#{System.unique_integer([:positive])}.jpg"
    relative_path = Path.join("images", name)
    path = Path.join(Brando.config(:media_path), relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.cp!(Path.expand("../../e2e/playwright/fixtures/image2.jpg", __DIR__), path)

    avatar =
      Brando.Repo.insert!(%Brando.Images.Image{
        path: relative_path,
        status: :processed,
        width: 292,
        height: 173,
        config_target: "image:Brando.Users.User:avatar",
        formats: [:jpg],
        sizes: %{"thumb" => relative_path, "small" => relative_path}
      })

    {name, avatar}
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
