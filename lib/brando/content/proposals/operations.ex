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
    * `placement` — `:append`, `{:before, uid}` or `{:after, uid}`, where `uid`
      is a root block of the field
    * `values` — var values by key
    * `texts` — `%{ref_name => text}` for text refs (safe rich-text HTML) and
      header refs (plain text)
    * `media` — `%{ref_name => {:image, id} | {:video, id}}`

  `uid` and `ref_uids` are frozen when the proposal is prepared, so every
  materialization — review, preview and apply — builds the same block.
  """
  @enforce_keys [:target, :module]
  defstruct [
    :target,
    :module,
    :uid,
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
  Put a library image or video into ref `ref` of the root block `block_uid`.
  `asset` is `{:image, id}` or `{:video, id}`.
  """
  @enforce_keys [:target, :block_uid, :ref, :asset]
  defstruct [:target, :block_uid, :ref, :asset, field: "blocks"]
end

defmodule Brando.Content.Proposals.SetBlockValues do
  @moduledoc "Set var values by key on the root block `block_uid`."
  @enforce_keys [:target, :block_uid, :values]
  defstruct [:target, :block_uid, :values, field: "blocks"]
end

defmodule Brando.Content.Proposals.SetBlockText do
  @moduledoc """
  Replace the text of ref `ref` on the root block `block_uid`: safe rich-text
  HTML for a text ref, plain text for a header ref.
  """
  @enforce_keys [:target, :block_uid, :ref, :text]
  defstruct [:target, :block_uid, :ref, :text, field: "blocks"]
end
