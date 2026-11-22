defmodule Brando.Test.Blocks do
  @moduledoc """
  Render blocks and modules as the site renders them, and add blocks to
  entries. Imported by `use Brando.Test`; see `Brando.Test`.
  """

  alias Brando.Content.{Block, Module, Seed}
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
  `Brando.Content.Seed.block/3` describes.
  """
  @spec build_block(Module.t() | integer(), keyword()) :: Block.t()
  def build_block(module, opts \\ []) do
    module
    |> Seed.block(opts[:user], Keyword.take(opts, [:vars, :refs]))
    |> Changeset.change(Keyword.take(opts, [:source, :type]))
    |> Changeset.apply_changes()
  end

  @doc """
  Add a block from `module` to `entry`'s block field and save the entry
  through its context, as saving the form would
  (`Brando.Content.Seed.add_blocks/4`). Returns the saved block.

  Options: `vars:` and `refs:` as for `render_block/2`, `field:` (the
  first block field by default), `sequence:` (after the existing blocks by
  default) and `user:`, who saves the entry.
  """
  @spec insert_block(struct(), Module.t() | integer(), keyword()) :: Block.t()
  def insert_block(%schema{} = entry, module, opts \\ []) do
    block = Seed.block(module, opts[:user], Keyword.take(opts, [:vars, :refs]))
    seed_opts = [field: opts[:field], at: opts[:sequence]] |> Enum.reject(&is_nil(elem(&1, 1)))
    {:ok, saved} = Seed.add_blocks(entry, [block], opts[:user], seed_opts)
    field = seed_opts[:field] || schema.__blocks_fields__() |> List.first() |> Map.fetch!(:name)
    uid = Changeset.get_field(block, :uid)

    saved |> Map.fetch!(:"entry_#{field}") |> Enum.find_value(&(&1.block.uid == uid && &1.block))
  end
end
