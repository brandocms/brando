defmodule Brando.Content.Proposals.CreateEntry do
  @moduledoc """
  Create an entry of `schema` with `fields` (string keys). The entry is always
  created as a draft. Other operations address it as `{:new, ref}`.
  """
  @enforce_keys [:schema, :ref]
  defstruct [:schema, :ref, fields: %{}]
end

defmodule Brando.Content.Proposals.SetFields do
  @moduledoc """
  Change attributes of an existing entry. `target` is `{schema, id}`.
  Publication fields and block fields are not settable this way.
  """
  @enforce_keys [:target, :fields]
  defstruct [:target, :fields]
end

defmodule Brando.Content.Proposals.InsertBlock do
  @moduledoc """
  Insert a block built from a module into a block field.

    * `target` — `{schema, id}` or `{:new, ref}`
    * `field` — the block field name, `"blocks"` by default
    * `module` — a module id or shared-library reference
    * `parent` — the uid of the block to insert into: a multi module block
      (which takes its child modules), a container or a slot. `nil` inserts a
      root block.
    * `placement` — `:append`, `{:before, uid}` or `{:after, uid}`, where `uid`
      is a block with the same parent
    * `values` — var values by key
    * `texts` — `%{ref_name => text}` for text refs (safe rich-text HTML) and
      header refs (plain text)
    * `media` — `%{ref_name => {:image, id} | {:video, id}}`

  `uid` and `ref_uids` are frozen when the proposal is prepared, so every
  materialization — review, preview and apply — builds the same block. A
  `uid` given in the operation lets later operations address the new block,
  for example to insert children into it.
  """
  @enforce_keys [:target, :module]
  defstruct [
    :target,
    :module,
    :uid,
    :parent,
    field: "blocks",
    placement: :append,
    values: %{},
    texts: %{},
    media: %{},
    ref_uids: %{}
  ]
end

defmodule Brando.Content.Proposals.SetBlockMedia do
  @moduledoc """
  Put a library image or video into ref `ref` of the block `block_uid`, at
  any depth of the field.
  `asset` is `{:image, id}` or `{:video, id}`.
  """
  @enforce_keys [:target, :block_uid, :ref, :asset]
  defstruct [:target, :block_uid, :ref, :asset, field: "blocks"]
end

defmodule Brando.Content.Proposals.SetBlockValues do
  @moduledoc """
  Set var values by key on the block `block_uid`, at any depth of the field.

  Text vars take strings, booleans a boolean and selects one of their options.
  Colours take `#rgb`/`#rrggbb(aa)`, dates and datetimes ISO 8601 strings,
  image and video vars `{:image | :video, id}`, and link vars a URL or
  `{:entry, schema, id}`.
  """
  @enforce_keys [:target, :block_uid, :values]
  defstruct [:target, :block_uid, :values, field: "blocks"]
end

defmodule Brando.Content.Proposals.SetBlockText do
  @moduledoc """
  Replace the text of ref `ref` on the block `block_uid`, at any depth of the
  field: safe rich-text HTML for a text ref, plain text for a header ref.
  """
  @enforce_keys [:target, :block_uid, :ref, :text]
  defstruct [:target, :block_uid, :ref, :text, field: "blocks"]
end

defmodule Brando.Content.Proposals.MoveBlock do
  @moduledoc """
  Move the block `block_uid`, keeping its row and its children.

  `placement` is `:append` (last among its current siblings), `{:before, uid}`
  or `{:after, uid}` next to any block of the field — the block moves to that
  block's parent — or `{:into, uid}`, the end of that block's children. The
  new parent must accept the block's module, as for `InsertBlock`.
  """
  @enforce_keys [:target, :block_uid, :placement]
  defstruct [:target, :block_uid, :placement, field: "blocks"]
end

defmodule Brando.Content.Proposals.DeleteBlock do
  @moduledoc """
  Remove the block `block_uid` and its children from the field, as deleting
  it in the block editor does.
  """
  @enforce_keys [:target, :block_uid]
  defstruct [:target, :block_uid, field: "blocks"]
end

defmodule Brando.Content.Proposals.SetBlockActive do
  @moduledoc """
  Turn the block `block_uid` on or off, or — with `ref` — one of its refs.
  An inactive block or ref is kept but not rendered, as when an editor
  switches it off.
  """
  @enforce_keys [:target, :block_uid, :active]
  defstruct [:target, :block_uid, :active, :ref, field: "blocks"]
end
