defmodule Brando.Content.Proposals.CreateEntry do
  @moduledoc """
  Create an entry of `schema` with `fields` (string keys). The entry is always
  created as a draft. Other operations address it as `{:new, ref}`.
  """
  @enforce_keys [:schema, :ref]
  defstruct [:schema, :ref, fields: %{}]
end

defmodule Brando.Content.Proposals.CreateTranslation do
  @moduledoc """
  Create the `language` version of `source` (`{schema, id}`) in its
  synchronized translation group, as the editor's Create translation does
  (`Brando.Translations.create_target/5`): an unpublished copy, linked as an
  alternate, with every text it copied marked to translate. A source not yet
  in a group becomes its source. Other operations name the new entry as
  `{:new, ref}`.
  """
  @enforce_keys [:source, :language, :ref]
  defstruct [:source, :language, :ref]

  @type t :: %__MODULE__{source: {module(), integer()}, language: String.t(), ref: String.t()}
end

defmodule Brando.Content.Proposals.Translate do
  @moduledoc """
  Answer one batch of a synchronized translation's work, as
  `translation_work` read it (`Brando.Translations.Work`).

    * `target` — the translation, `{schema, id}`, or `{:new, ref}` for the
      one a `CreateTranslation` in the same proposal creates
    * `source_digest` — the batch's token
    * `texts` — the translated text by unit key
    * `reviewed` — the keys of units that are right as they are

  Applied, the translation is saved as its form saves it
  (`Brando.Translations.save_work/5`): its pending version with the texts
  written in, and every answered work item resolved.
  """
  @enforce_keys [:target, :source_digest]
  defstruct [:target, :source_digest, texts: %{}, reviewed: []]

  @type t :: %__MODULE__{
          target: {module(), integer()} | {:new, String.t()},
          source_digest: String.t(),
          texts: map(),
          reviewed: [String.t()]
        }
end

defmodule Brando.Content.Proposals.SyncTranslation do
  @moduledoc """
  Save the synchronized translation `target` (`{schema, id}`) with its
  pending version as it is, as saving its form without editing it does:
  links, media and source-controlled values follow the source, and the work
  items that save resolves (`relinked`, `shared_update`) are resolved. Text
  units stay open, for `Translate`; `awaiting_translation` items stay open
  until the linked content's version in this language exists.

  `takes` is what the save takes, counted from the translation's open work
  when the proposal is prepared (string keys: `"links"`, `"media"`,
  `"values"`), and checked again at approve and apply.
  `Brando.Content.Proposals.prepare/2` always counts it, never taking it
  from the operation it is given.
  """
  @enforce_keys [:target]
  defstruct [:target, :takes]

  @type t :: %__MODULE__{target: {module(), integer()} | {:new, String.t()}, takes: map() | nil}
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
    * `texts` — `%{ref_name => text}`: safe rich-text HTML for text refs, plain
      text for headers, markdown, safe HTML for html refs, one safe `<svg>` for
      svg refs and an https embed URL for map refs
    * `media` — `%{ref_name => asset}`, an asset as for `SetBlockMedia`
    * `configs` — `%{ref_name => settings}`, as for `SetRefConfig`

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
    configs: %{},
    ref_uids: %{}
  ]
end

defmodule Brando.Content.Proposals.SetBlockMedia do
  @moduledoc """
  Put library media into ref `ref` of the block `block_uid`, at any depth of
  the field. `asset` is `{:image, id}`, `{:video, id}`, `{:file, id}`, or
  `{:gallery, [{:image | :video, id}]}` — a gallery's full, ordered content.
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
  Replace the content of ref `ref` on the block `block_uid`, at any depth of
  the field. What a ref takes is listed under `InsertBlock`'s `texts`.
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

defmodule Brando.Content.Proposals.CopyBlock do
  @moduledoc """
  Copy the block `block_uid` with everything below it, as pasting a copied
  block does. `placement` is as for `MoveBlock`; `:append` puts the copy last
  among the original's siblings. The new parent must take the module.

  `uid` is the copy's uid, frozen at prepare. The copies of the blocks below
  it take uids derived from it (`BlockTree.copy_uid/2`), so review, preview
  and apply build the same tree.

  With `to_target` (and `to_field`), the copy goes to another entry or block
  field; placement anchors are then blocks there. Such a copy is of the
  saved block. A move to another entry is a copy and a `DeleteBlock`.
  """
  @enforce_keys [:target, :block_uid]
  defstruct [:target, :block_uid, :uid, :to_target, :to_field, placement: :append, field: "blocks"]
end

defmodule Brando.Content.Proposals.SetBlockDetails do
  @moduledoc """
  Set the `anchor` (the id a link can jump to) and/or the `description` (the
  editor's own label) of the block `block_uid`. `nil` leaves one unchanged;
  `""` clears it.
  """
  @enforce_keys [:target, :block_uid]
  defstruct [:target, :block_uid, :anchor, :description, field: "blocks"]
end

defmodule Brando.Content.Proposals.SetRefConfig do
  @moduledoc """
  Change the settings of ref `ref` on the block `block_uid`: a heading's
  level, a picture's alt text, title, credits or link, a video's autoplay or
  loop, a gallery's display, a file's label — any field of the ref type's
  data except its content (text, media, sizes), which have their own
  operations. `config` maps field names to values, cast by the ref type.
  """
  @enforce_keys [:target, :block_uid, :ref, :config]
  defstruct [:target, :block_uid, :ref, :config, field: "blocks"]
end

defmodule Brando.Content.Proposals.SetBlockTable do
  @moduledoc """
  Replace the table rows of the block `block_uid`. Its module's table
  template defines each row's variables; `rows` is a list of
  `%{var_key => value}`, values as for `SetBlockValues`. Keys a row leaves out
  keep the template's defaults.
  """
  @enforce_keys [:target, :block_uid, :rows]
  defstruct [:target, :block_uid, :rows, field: "blocks"]
end

defmodule Brando.Content.Proposals.SetBlockSelection do
  @moduledoc """
  Choose the entries a selection datasource block shows, in order, as
  identifier ids from the datasource's own options (the `list_selection_options`
  tool). A single-entry datasource takes one.
  """
  @enforce_keys [:target, :block_uid, :identifiers]
  defstruct [:target, :block_uid, :identifiers, field: "blocks"]
end

defmodule Brando.Content.Proposals.ReplaceImageFile do
  @moduledoc """
  Give library image `asset` (`{:image, id}`, OLD) the file of library image
  `with` (`{:image, id}`, NEW), keeping OLD's id, focal point, texts, folder
  and every place it is used. NEW's record goes, since its file is now OLD's
  and nothing used it. See `Brando.Content.Proposals.ImageReplacement`.

  `old` and `new` are what the two files were when the proposal was
  prepared, frozen with it (string keys: `"path"`, `"width"`, `"height"`,
  `"content_hash"`, `"type"`, `"bytes"`, `"sizes"`, `"formats"`, `"cdn"`,
  `"focal"`): the review shows them, and the proposal is refused when
  either file changed since. `Brando.Content.Proposals.prepare/2` always
  takes them from the library, never from the operation it is given.
  """
  @enforce_keys [:asset, :with]
  defstruct [:asset, :with, :old, :new]

  @type t :: %__MODULE__{}
end
