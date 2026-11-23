defmodule Brando.Content.Seed do
  @moduledoc """
  Create content from code: seed scripts, demo content, imports and data
  migrations.

  Every function acts as a user and goes through the contexts the admin
  uses, so the user's rights are checked, and identifiers, revisions, the
  activity log, rendering and cache eviction happen as when an editor saves.
  There is no second write path to keep in step with the admin.

      alias Brando.Content.Seed

      {:ok, image} = Seed.upload_image("priv/seeds/lobby.jpg", user, alt: "The lobby")
      block = Seed.block("image-row", user, refs: %{"picture" => image}, vars: %{"wide" => true})

      {:ok, page} =
        Seed.create_entry(Brando.Pages.Page, %{title: "Lobby", uri: "lobby", language: "en"}, user,
          blocks: [block]
        )

  The [Seeding guide](seeding.html) has a whole seed script, and what to do
  with several sites.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.BlockContent
  alias Brando.Content.Blocks
  alias Brando.Content.Module
  alias Brando.Content.RefGuard
  alias Brando.Images.Intake
  alias Brando.Uploads
  alias Brando.Uploads.ContentType
  alias Ecto.Changeset

  @asset_hint %{"gallery" => "a list of images, videos or paths", "file" => "a Brando.Files.File"}

  @doc """
  Stores the image at `path` in the media library, as an editor's upload
  would, and returns `{:ok, image}` or `{:error, message}`.

  The library keeps one image per file: when it already has the same bytes,
  that image is returned and nothing is stored, so a seed script can run
  again. Its sizes are made in the background (Oban), and the entries that
  show it are rendered again when they are done.

  Options:

    * `:folder` — the library folder, below the image config's upload path
    * `:alt`, `:title` — the image's texts
    * `:focal` — its focal point, `%{x: 50, y: 50}` by default

  ## Example

      {:ok, image} = Seed.upload_image("priv/seeds/lobby.jpg", user, folder: "seeds", alt: "The lobby")
  """
  @spec upload_image(Path.t(), Brando.Users.User.t(), keyword()) :: {:ok, Brando.Images.Image.t()} | {:error, String.t()}
  def upload_image(path, user, opts \\ []) do
    opts = Keyword.validate!(opts, [:folder, :alt, :title, :focal])
    ctx = Intake.context(user, opts[:folder])
    attrs = opts |> Keyword.take([:alt, :title, :focal]) |> Map.new()

    with {:ok, head} <- head(path),
         {:ok, type, ext} <- Intake.image_type(head, ctx.cfg) do
      case Intake.store(path, Intake.filename(Path.basename(path), ext, "image"), type, ctx, &{:stored, &1}, attrs) do
        {:error, message} -> {:error, message}
        {_stored_or_reused, image} -> {:ok, image}
      end
    end
  end

  @doc """
  Stores the video file at `path` as an uploaded video, as an editor's upload
  would, and returns `{:ok, video}` or `{:error, message}`. Unlike an image,
  the same file uploaded twice is stored twice.

  For a video hosted elsewhere (YouTube, Vimeo), create it with
  `Brando.Videos` and pass the video to `block/3`.

      {:ok, video} = Seed.upload_video("priv/seeds/intro.mp4", user)
  """
  @spec upload_video(Path.t(), Brando.Users.User.t()) :: {:ok, Brando.Videos.Video.t()} | {:error, String.t()}
  def upload_video(path, user) do
    {cfg, config_target} = Uploads.resolve_video_config(nil)

    with {:ok, head} <- head(path),
         [_ | _] = types <- ContentType.video(head) do
      type = video_type(types, path, cfg.allowed_mimetypes)
      entry = %{client_name: Path.basename(path), client_type: type, client_size: File.stat!(path).size}
      Uploads.store_upload(%{path: path, config_target: config_target}, entry, cfg, user)
    else
      {:error, message} -> {:error, message}
      [] -> {:error, "#{path} is not a video file."}
    end
  end

  # A container can be several types (an MP4 or a QuickTime file): the one
  # its extension names comes first, then the first the configuration allows
  defp video_type(types, path, allowed) do
    by_name = MIME.from_path(path)
    types = if by_name in types, do: [by_name | List.delete(types, by_name)], else: types
    Enum.find(types, hd(types), &(allowed == ["*"] or &1 in allowed))
  end

  defp head(path) do
    case ContentType.head(path) do
      {:ok, head} -> {:ok, head}
      {:error, reason} -> {:error, "#{path} could not be read: #{inspect(reason)}"}
    end
  end

  @doc """
  A new block of `module` (a saved `Brando.Content.Module`, its id, or the
  `uid` its module definition gives it), as the block editor inserts it,
  with its module's default content and what `opts` give. Pass it to
  `create_entry/4` or `add_blocks/4` to save it.

  `user` is the block's creator, and uploads the files named by path.

    * `refs:` — a map of ref names to their content:
      * a string: the text of a text, header or other text ref, or the path
        of a file to upload for a picture ref (an image), a video ref (a
        video) or a media ref (by what the file holds), as `upload_image/3`
        and `upload_video/2` do
      * a `Brando.Images.Image`, `Brando.Videos.Video` or `Brando.Files.File`
      * a list of images, videos or paths for a gallery ref: the block gets
        a new gallery of them. A saved `Brando.Galleries.Gallery` is used as is.
      * a map of the ref's data fields, such as `%{text: "<p>Hi</p>", level: 2}`.
        An HTML or SVG ref takes its markup this way, from a superuser only,
        as in the editor (`Brando.Content.RefGuard`).
      * `false`, to switch the ref off

      A ref takes the media its module gives it: a picture ref an image, a
      gallery ref a gallery. A media ref, which an editor can fill with a
      picture, a video or a gallery, takes the type of what it is given, if
      the module makes that type available, with the module's template for
      that type, as in the editor.

    * `vars:` — a map of var keys to values: a string, a boolean, an image,
      video or file (or a path to one, for an image or video var), a list of
      images or videos for a gallery var, and for a link var a URL or an
      entry to link to.

  An unknown ref or var name raises `ArgumentError`, naming the ones the
  module has, as do media a ref does not take (naming what it takes), a
  string for a ref that holds no text, markup from a user who is not a
  superuser, and a file that cannot be uploaded. A file path or a list for
  a gallery needs `user`.

      block =
        Seed.block("image-row", user,
          refs: %{"picture" => "priv/seeds/lobby.jpg", "caption" => "<p>The lobby</p>"},
          vars: %{"wide" => true}
        )
  """
  @spec block(Module.t() | integer() | String.t(), Brando.Users.User.t(), keyword()) :: Changeset.t()
  def block(module, user, opts \\ [])

  def block(uid, user, opts) when is_binary(uid) do
    case Brando.Repo.one(from(m in Module, where: m.uid == ^uid and is_nil(m.deleted_at), select: m.id)) do
      nil -> raise ArgumentError, "there is no module with the uid #{inspect(uid)}"
      id -> block(id, user, opts)
    end
  end

  # A shared library's module keeps its origin: its id may name a local module too
  def block(%Module{id: id} = module, user, opts) when not is_nil(id),
    do: build({Map.get(module, :library_origin) || :local, id}, user, opts)

  def block(%Module{}, _user, _opts), do: raise(ArgumentError, "block/3 needs a saved module")
  def block(module_id, user, opts) when is_integer(module_id), do: build({:local, module_id}, user, opts)

  defp build({origin, module_id}, user, opts) do
    opts = Keyword.validate!(opts, refs: %{}, vars: %{})
    module = Brando.Content.fetch_module(module_id, origin)

    {origin, module_id}
    |> Blocks.build_module_block(user && user.id, nil, nil, :module)
    |> put_refs(module, Map.new(opts[:refs]), user)
    |> put_vars(Map.new(opts[:vars]), user)
  end

  defp put_refs(block, module, given, user) do
    refs = Changeset.get_assoc(block, :refs)
    unknown!(given, Enum.map(refs, &Changeset.get_field(&1, :name)), "ref")

    refs =
      Enum.map(refs, fn ref ->
        case Map.fetch(given, Changeset.get_field(ref, :name)) do
          {:ok, value} -> put_ref(ref, value, module, user)
          :error -> ref
        end
      end)

    Changeset.put_assoc(block, :refs, refs)
  end

  defp put_ref(ref, false, _module, _user), do: Changeset.put_change(ref, :active, false)

  defp put_ref(ref, %Brando.Galleries.Gallery{id: id}, module, user) when not is_nil(id),
    do: put_media(ref, {:gallery, id}, module, user)

  defp put_ref(ref, items, module, user) when is_list(items) do
    accepts!(ref, :gallery, module)
    user!(user, "a new gallery")
    put_media(ref, {:gallery, Enum.map(items, &media!(&1, user))}, module, user)
  end

  defp put_ref(ref, value, module, user) when is_binary(value) do
    case Changeset.get_field(ref, :data) do
      %{type: type} when type in ~w(picture video media) ->
        kind = path_kind(value)
        accepts!(ref, kind, module)
        put_media(ref, upload!(kind, value, user), module, user)

      %{type: type} when type in ~w(gallery file) ->
        raise ArgumentError, "a #{type} ref takes #{@asset_hint[type]}"

      _ ->
        BlockContent.put_text(ref, value)
    end
  end

  defp put_ref(ref, %struct{} = asset, module, user)
       when struct in [Brando.Images.Image, Brando.Videos.Video, Brando.Files.File],
       do: put_media(ref, media!(asset, user), module, user)

  defp put_ref(ref, fields, _module, user) when is_map(fields) do
    %{type: type, data: data} = block = Changeset.get_field(ref, :data)
    fields = Map.new(fields, fn {key, value} -> {to_existing_atom(key), value} end)

    markup = Enum.filter(RefGuard.markup_fields(type), &Map.has_key?(fields, &1))

    if markup != [] and not RefGuard.may_change_markup?(user) do
      raise ArgumentError,
            "the ref #{inspect(Changeset.get_field(ref, :name))} holds markup only a superuser changes " <>
              "(#{Enum.map_join(markup, ", ", &inspect/1)})"
    end

    Changeset.put_change(ref, :data, %{block | data: struct!(data, fields)})
  end

  defp put_media(ref, {kind, _} = media, module, user) do
    accepts!(ref, kind, module)
    BlockContent.put_media(ref, media, module, user)
  end

  @kind_names %{
    image: "an image",
    video: "a video",
    file: "a file",
    gallery: "a gallery (a list of images, videos or paths)"
  }

  # As the editor and proposals check: a ref takes the media kinds its
  # module's definition makes available
  defp accepts!(ref, kind, module) do
    name = Changeset.get_field(ref, :name)
    accepted = module.refs |> Enum.find(&(&1.name == name)) |> BlockContent.accepts()

    unless kind in accepted do
      takes = if accepted == [], do: "no media", else: Enum.map_join(accepted, " or ", &@kind_names[&1])
      raise ArgumentError, "the ref #{inspect(name)} takes #{takes}, not #{@kind_names[kind]}"
    end
  end

  defp user!(nil, what), do: raise(ArgumentError, "#{what} needs a user (`user:` in Brando.Test's helpers)")
  defp user!(_user, _what), do: :ok

  defp put_vars(block, given, _user) when given == %{}, do: block

  defp put_vars(block, given, user) do
    vars = Changeset.get_assoc(block, :vars)
    unknown!(given, Enum.map(vars, &Changeset.get_field(&1, :key)), "var")
    types = Map.new(vars, &{Changeset.get_field(&1, :key), Changeset.get_field(&1, :type)})
    values = Map.new(given, fn {key, value} -> {key, var_value(Map.fetch!(types, key), value, user)} end)
    BlockContent.put_values(block, values, user)
  end

  defp var_value(_type, value, _user) when is_boolean(value), do: value

  defp var_value(:gallery, items, user) when is_list(items) do
    user!(user, "a new gallery")
    {:gallery, Enum.map(items, &media!(&1, user))}
  end

  defp var_value(type, path, user) when type in [:image, :video] and is_binary(path), do: upload!(type, path, user)
  defp var_value(:link, %{__struct__: schema, id: id}, _user) when is_integer(id), do: {:entry, schema, id}

  defp var_value(_type, %struct{} = asset, user)
       when struct in [Brando.Images.Image, Brando.Videos.Video, Brando.Files.File],
       do: media!(asset, user)

  defp var_value(_type, value, _user), do: to_string(value)

  defp media!(%Brando.Images.Image{id: id}, _user), do: {:image, id}
  defp media!(%Brando.Videos.Video{id: id}, _user), do: {:video, id}
  defp media!(%Brando.Files.File{id: id}, _user), do: {:file, id}

  defp media!(path, user) when is_binary(path), do: upload!(path_kind(path), path, user)

  # A path to a video file is uploaded as a video, any other as an image
  defp path_kind(path) do
    case head(path) do
      {:ok, head} -> if ContentType.video(head) == [], do: :image, else: :video
      # The upload says what is wrong
      {:error, _} -> :image
    end
  end

  defp upload!(kind, path, user) do
    user!(user, "uploading #{path}")
    result = if kind == :video, do: upload_video(path, user), else: upload_image(path, user)

    case result do
      {:ok, asset} -> media!(asset, user)
      {:error, message} -> raise ArgumentError, "could not upload #{path}: #{message}"
    end
  end

  defp unknown!(given, names, kind, owner \\ "the module") do
    case Map.keys(given) -- names do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "#{owner} has no #{kind} #{Enum.map_join(unknown, ", ", &inspect/1)}; it has #{inspect(names)}"
    end
  end

  defp to_existing_atom(key) when is_atom(key), do: key
  defp to_existing_atom(key), do: String.to_existing_atom(key)

  @doc """
  Creates an entry of `schema` from `params`, with `blocks` from `block/3`,
  through its context's `create_*` function, as the admin form creates it:
  rendered, with an identifier and a revision. Returns `{:ok, entry}`, or
  `{:error, changeset}`, or `{:error, :forbidden}` when `user` may not
  create it.

  `params` are what the form would send: a language is given as a string
  (`"en"`) or an atom.

    * `blocks:` — the blocks of the first block field, or a keyword list of
      block fields and their blocks: `[blocks: [...], footer: [...]]`

  ## Example

      {:ok, page} =
        Seed.create_entry(Brando.Pages.Page, %{title: "Lobby", uri: "lobby", language: "en"}, user,
          blocks: [Seed.block("image-row", user, refs: %{"picture" => image})]
        )
  """
  @spec create_entry(module(), map(), Brando.Users.User.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def create_entry(schema, params, user, opts \\ []) do
    opts = Keyword.validate!(opts, blocks: [])
    # Every block field, empty or not: an unsaved entry has them unloaded
    fields = Map.new(schema.__blocks_fields__(), &{&1.name, []})

    schema
    |> struct()
    |> schema.changeset(params, user, nil, [])
    |> put_blocks(Map.merge(fields, by_field(schema, opts[:blocks])))
    |> save(:create, user)
  end

  @doc """
  Adds `blocks` from `block/3` to `entry`'s first block field, after the
  blocks it has, and saves it through its context's `update_*` function, as
  the admin form saves it. Returns `{:ok, entry}`, `{:error, changeset}` or
  `{:error, :forbidden}`.

    * `field:` — another block field, by name
    * `at:` — the position of the first new block, from 0. Default: after
      the last.

  An entry in the trash raises `ArgumentError`. Calls for one entry must not
  run at the same time: each saves the blocks it read, and the entry's HTML
  can end up without the other's.

  ## Example

      {:ok, page} = Seed.add_blocks(page, [Seed.block("text", user, refs: %{"body" => "<p>More</p>"})], user)
  """
  @spec add_blocks(struct(), [Changeset.t()], Brando.Users.User.t(), keyword()) :: {:ok, struct()} | {:error, term()}
  def add_blocks(%schema{id: id} = entry, blocks, user, opts \\ []) do
    Brando.Tenant.ensure_current!(entry)
    opts = Keyword.validate!(opts, [:field, :at])
    field = opts[:field] || first_field!(schema)
    entry = live_entry!(schema, id)
    saved = entry |> Map.fetch!(:"entry_#{field}") |> Enum.map(&Changeset.change/1)

    entry
    |> schema.changeset(%{}, user, nil, [])
    |> put_blocks(%{field => {saved, blocks, opts[:at] || length(saved)}})
    |> save(:update, user)
  end

  # `EntryQuery.get/2` finds an entry in the trash as well
  defp live_entry!(schema, id) do
    case Brando.Blueprint.EntryQuery.get(schema, id) do
      {:ok, %{deleted_at: deleted_at}} when not is_nil(deleted_at) ->
        raise ArgumentError, "#{inspect(schema)} #{id} is in the trash: restore it before adding blocks"

      {:ok, entry} ->
        entry

      {:error, _} ->
        raise ArgumentError, "there is no #{inspect(schema)} #{id}"
    end
  end

  defp by_field(schema, [{field, _blocks} | _] = fields) when is_atom(field) do
    known = Enum.map(schema.__blocks_fields__(), & &1.name)
    unknown!(Map.new(fields), known, "block field", inspect(schema))
    Map.new(fields)
  end

  defp by_field(_schema, []), do: %{}
  defp by_field(schema, blocks) when is_list(blocks), do: %{first_field!(schema) => blocks}

  defp first_field!(schema) do
    case schema.__blocks_fields__() do
      [%{name: name} | _] -> name
      [] -> raise ArgumentError, "#{inspect(schema)} has no block field"
    end
  end

  defp put_blocks(%Changeset{data: %schema{}} = changeset, fields) do
    fields
    |> Enum.reduce(changeset, fn {field, blocks}, changeset ->
      join = Elixir.Module.concat(schema, Macro.camelize(to_string(field)))

      joins =
        case blocks do
          {saved, new, at} -> List.insert_at(saved, at, Enum.map(new, &new_join(join, &1))) |> List.flatten()
          new -> Enum.map(new, &new_join(join, &1))
        end

      Changeset.put_assoc(changeset, :"entry_#{field}", Enum.with_index(joins, &Changeset.change(&1, sequence: &2)))
    end)
    |> Blocks.render_block_fields()
  end

  defp new_join(join, block) do
    join
    |> struct()
    |> Changeset.change()
    |> Changeset.put_assoc(:block, Changeset.put_change(block, :source, join))
    |> Map.put(:action, :insert)
  end

  defp save(%Changeset{data: %schema{}} = changeset, action, user) do
    context = schema.__modules__().context
    fun = :"#{action}_#{schema.__naming__().singular}"

    with {:ok, entry} <- apply(context, fun, [changeset, user]) do
      Brando.Blueprint.AfterSave.run(schema, entry, changeset, user)
      {:ok, entry}
    end
  end

  @doc """
  Params for a menu item that links to `target`, a URL or an entry, for
  `Brando.Navigation.create_menu/2`. `text` is the link's text; for an entry
  it may be `nil`, to show the entry's title.

    * `:key` — the item's key. Without one it follows the link, as an
      editor's item does (`Brando.Navigation.Item.DeriveKey`): `text` in
      `snake_case`, or the linked entry's title
    * `:new_tab` — open the link in a new tab

  ## Example

      Brando.Navigation.create_menu(
        %{
          title: "Main menu",
          key: "main",
          language: "en",
          status: :published,
          items: [Seed.menu_item("Home", "/"), Seed.menu_item(nil, about_page)]
        },
        user
      )
  """
  @spec menu_item(String.t() | nil, String.t() | struct(), keyword()) :: map()
  def menu_item(text, target, opts \\ []) do
    opts = Keyword.validate!(opts, [:key, :new_tab])

    item = %{
      status: :published,
      link:
        Map.merge(
          %{type: :link, key: "link", label: "Link", link_text: text, link_target_blank: opts[:new_tab] || false},
          link(target)
        )
    }

    if key = opts[:key], do: Map.put(item, :key, key), else: item
  end

  defp link(url) when is_binary(url), do: %{link_type: :url, value: url}

  defp link(%schema{id: id}) do
    {:ok, identifier} = Brando.Content.get_identifier(schema, %{id: id})
    %{link_type: :identifier, identifier_id: identifier.id}
  end

  @doc """
  Sets the values of the global set `key` in `language` (a string or an
  atom), as the Globals screen does: `values` maps var keys to a string or,
  for a boolean var, a boolean. Vars not named keep their values. Returns
  `{:ok, global_set}`, `{:error, :not_found}`, `{:error, changeset}` or
  `{:error, :forbidden}`.

      {:ok, _set} = Seed.put_globals("contact", "en", %{"email" => "hi@acme.test"}, user)
  """
  @spec put_globals(String.t(), String.t() | atom(), map(), Brando.Users.User.t()) ::
          {:ok, Brando.Sites.GlobalSet.t()} | {:error, term()}
  def put_globals(key, language, values, user) do
    query =
      from(g in Brando.Sites.GlobalSet,
        where: g.key == ^key and g.language == ^to_string(language),
        preload: :vars
      )

    case Brando.Repo.one(query) do
      nil ->
        {:error, :not_found}

      set ->
        unknown!(values, Enum.map(set.vars, & &1.key), "var", "the global set")

        rows = for var <- set.vars, Map.has_key?(values, var.key), do: global_row(var, Map.fetch!(values, var.key))
        Brando.Sites.update_global_values(set, %{"vars" => rows}, user)
    end
  end

  defp global_row(var, value) when is_boolean(value), do: %{"id" => var.id, "value_boolean" => value}
  defp global_row(var, value), do: %{"id" => var.id, "value" => to_string(value)}

  @doc """
  Renders `entry`'s blocks again and stores the HTML, evicting the cached
  entry, as `Brando.Content.Blocks.render_entry/2` does. The functions in
  this module render what they save; call this after changing what an
  entry's blocks show from outside them, such as a module's template. After
  writing to the database without the contexts (`Repo.update_all/3`), clear
  the caches first with `Brando.Cache.clear_content/1`.

      {:ok, page} = Seed.render(page)
  """
  @spec render(struct()) :: {:ok, struct()} | {:error, term()}
  def render(%schema{id: id}), do: Blocks.render_entry(schema, id)
end
