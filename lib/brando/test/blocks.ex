defmodule Brando.Test.Blocks do
  @moduledoc """
  Render blocks and modules as the site renders them, and add blocks to
  entries. Imported by `use Brando.Test`; see `Brando.Test`.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Block, Blocks, Module, Ref, Var}
  alias Ecto.Changeset

  @doc """
  Render a block, or a module with its default content, to HTML exactly as
  the site would: through the configured parser, the Liquid pass, footnotes,
  `$timestamp` and form delivery.

  `block_or_module` is a `Brando.Content.Block` (or an entry's join row,
  `%{block: block}`), a saved `Brando.Content.Module`, or a module id. A
  module is rendered as a block freshly inserted from it, with its default
  refs and vars, then:

    * `vars:` — a map of var keys to values: `%{"heading" => "Hello", "wide" => true}`.
      A boolean var takes a boolean; an image, file or video var takes the
      asset struct.
    * `refs:` — a map of ref names to their content: a map of the ref
      block's data fields (`%{"body" => %{text: "<p>Hi</p>"}}`), an
      image, video, file or gallery struct for a media ref, or `false` to
      switch the ref off.

  Other options:

    * `entry:` — the entry the block belongs to, available to the template
      as `entry`. Default `nil`.
    * `conn:` — a conn, for templates that read `request`.

  Rendering reads modules, containers and fragments from the database, so the
  module must be saved.

      html = render_block(module, vars: %{"heading" => "Lobby"}, refs: %{"body" => %{text: "<p>Hi</p>"}})
      assert html =~ "<h2>Lobby</h2>"
  """
  @spec render_block(Block.t() | Module.t() | map() | integer(), keyword()) :: String.t()
  def render_block(block_or_module, opts \\ [])

  def render_block(%Module{} = module, opts), do: module |> build_block(opts) |> render_block(opts)
  def render_block(module_id, opts) when is_integer(module_id), do: module_id |> build_block(opts) |> render_block(opts)
  def render_block(%{block: %Block{} = block}, opts), do: render_block(block, opts)

  def render_block(%Block{} = block, opts) do
    parse_opts = Keyword.take(opts, [:conn, :footnotes, :footnote_scope])

    [%{block: block}]
    |> Brando.Villain.parse(Keyword.get(opts, :entry), parse_opts)
    |> Brando.HTML.replace_timestamp()
    |> Brando.Forms.Delivery.finalize()
  end

  @doc """
  An unsaved `Brando.Content.Block` for `module` (a saved module or its id),
  as the block editor inserts it, with `vars:` and `refs:` applied as
  `render_block/2` describes.
  """
  @spec build_block(Module.t() | integer(), keyword()) :: Block.t()
  def build_block(module, opts \\ [])
  def build_block(%Module{id: id}, opts) when not is_nil(id), do: build_block(id, opts)

  def build_block(module_id, opts) when is_integer(module_id) do
    block =
      module_id
      |> Blocks.build_module_block(user_id(opts[:user]), nil, opts[:source], opts[:type] || :module)
      |> Changeset.apply_changes()

    %{
      block
      | vars: apply_vars(block.vars, Map.new(Keyword.get(opts, :vars, %{}))),
        refs: apply_refs(block.refs, Map.new(Keyword.get(opts, :refs, %{})))
    }
  end

  def build_block(%Module{}, _opts), do: raise(ArgumentError, "build_block/2 needs a saved module")

  defp apply_vars(vars, overrides) do
    unknown = Map.keys(overrides) -- Enum.map(vars, & &1.key)

    if unknown != [] do
      raise ArgumentError,
            "the module has no var #{Enum.map_join(unknown, ", ", &inspect/1)}; it has #{inspect(Enum.map(vars, & &1.key))}"
    end

    Enum.map(vars, fn %Var{key: key} = var ->
      case Map.fetch(overrides, key) do
        {:ok, value} -> put_var(var, value)
        :error -> var
      end
    end)
  end

  defp put_var(var, value) when is_boolean(value), do: %{var | value_boolean: value}
  defp put_var(var, %Brando.Images.Image{} = image), do: %{var | image: image, image_id: image.id}
  defp put_var(var, %Brando.Files.File{} = file), do: %{var | file: file, file_id: file.id}
  defp put_var(var, %Brando.Videos.Video{} = video), do: %{var | video: video, video_id: video.id}
  defp put_var(var, value), do: %{var | value: to_string(value)}

  defp apply_refs(refs, overrides) do
    unknown = Map.keys(overrides) -- Enum.map(refs, & &1.name)

    if unknown != [] do
      raise ArgumentError,
            "the module has no ref #{Enum.map_join(unknown, ", ", &inspect/1)}; it has #{inspect(Enum.map(refs, & &1.name))}"
    end

    Enum.map(refs, fn %Ref{name: name} = ref ->
      case Map.fetch(overrides, name) do
        {:ok, value} -> put_ref(ref, value)
        :error -> ref
      end
    end)
  end

  defp put_ref(ref, false), do: %{ref | active: false}
  defp put_ref(ref, %Brando.Images.Image{} = image), do: %{ref | image: image, image_id: image.id}
  defp put_ref(ref, %Brando.Videos.Video{} = video), do: %{ref | video: video, video_id: video.id}
  defp put_ref(ref, %Brando.Files.File{} = file), do: %{ref | file: file, file_id: file.id}
  defp put_ref(ref, %Brando.Galleries.Gallery{} = gallery), do: %{ref | gallery: gallery, gallery_id: gallery.id}

  defp put_ref(%Ref{data: %{data: data} = block} = ref, fields) when is_map(fields) do
    fields = Map.new(fields, fn {key, value} -> {to_existing_atom(key), value} end)
    %{ref | data: %{block | data: struct!(data, fields)}}
  end

  defp to_existing_atom(key) when is_atom(key), do: key
  defp to_existing_atom(key), do: String.to_existing_atom(key)

  @doc """
  Add a block from `module` to `entry`'s block field and render the entry
  again, as saving the form would. Returns the saved block.

  Options: `vars:` and `refs:` as for `render_block/2`, `field:` (the
  first block field by default), `sequence:` (after the existing blocks by
  default) and `user:`.
  """
  @spec insert_block(struct(), Module.t() | integer(), keyword()) :: Block.t()
  def insert_block(%schema{id: entry_id} = entry, module, opts \\ []) do
    field = opts[:field] || schema.__blocks_fields__() |> List.first() |> Map.fetch!(:name)
    join = Elixir.Module.concat([schema, Phoenix.Naming.camelize(to_string(field))])
    block = build_block(module, opts)

    saved =
      block.module_id
      |> Blocks.build_module_block(user_id(opts[:user]), nil, join, :module)
      |> Changeset.put_assoc(:refs, Enum.map(block.refs, &unload(&1, %Ref{}, [:image, :video, :file, :gallery])))
      |> Changeset.put_assoc(:vars, Enum.map(block.vars, &unload(&1, %Var{}, [:image, :video, :file])))
      |> Brando.Repo.insert!()

    sequence =
      opts[:sequence] ||
        Brando.Repo.aggregate(from(j in join, where: j.entry_id == ^entry_id), :count)

    Brando.Repo.insert!(struct(join, entry_id: entry_id, block_id: saved.id, sequence: sequence))
    {:ok, _} = Blocks.render_entry(schema, entry.id)
    saved
  end

  # The asset is saved already; the block keeps its id only.
  defp unload(struct, empty, assocs), do: Map.merge(struct, Map.take(empty, assocs))

  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end
