defmodule Brando.Content.VarAttrs do
  @moduledoc """
  The castable var field lists, and the subset the block editor round-trips
  through hidden inputs for an unsaved var.

  A leaf module on purpose. The block editor's ref renderer reads
  `carried/0` into a module attribute — the list has to be a compile-time
  constant or LiveView re-sends the whole comprehension on every diff — and
  reading it off `Brando.Content.Block` gave the block editor a compile-time edge
  into a Blueprint schema, which is inside Blueprint's compile-connected
  component. This module depends on nothing, so the same value costs no edge.
  See issue #2737.

  `Brando.Content.Block` re-exports both lists; call them there when you are
  already in schema code.
  """

  @all [
    :type,
    :label,
    :placeholder,
    :key,
    :value,
    :value_boolean,
    :placement,
    :new_row,
    :instructions,
    :color_picker,
    :color_opacity,
    :link_text,
    :link_type,
    :link_identifier_schemas,
    :link_target_blank,
    :link_allow_custom_text,
    :width,
    :sequence,
    :creator_id,
    :module_id,
    :page_id,
    :block_id,
    :palette_id,
    :identifier_id,
    :global_set_id,
    :table_template_id,
    # Media a var can carry. The editor renders and commits all four
    # (`render_var.ex`, `block.ex`'s `commit_var_data`), so omitting any of them
    # here means the cast silently drops it and the value never reaches the DB.
    :image_id,
    :file_id,
    :video_id,
    :gallery_id,
    # Upload/picker configuration for media vars, set through the var's config UI
    :config_target,
    :gallery_image_config_target,
    :gallery_video_config_target,
    :gallery_allowed_types
  ]

  # Ownership and parentage, excluded from what the DOM is allowed to carry:
  # `creator_id` is forced server-side by `Block.var_changeset/4`, and the owner
  # FKs are set by whichever schema's `cast_assoc(:vars, …)` builds the var.
  # `palette_id` and `identifier_id` are deliberately absent — for a palette or
  # identifier var, those *are* the value.
  @owner [:creator_id, :module_id, :page_id, :block_id, :global_set_id, :table_template_id]

  @doc "Every var field `Brando.Content.Block` casts."
  @spec all() :: [atom()]
  def all, do: @all

  @doc "The owner and creator fields the DOM is never allowed to supply."
  @spec owner() :: [atom()]
  def owner, do: @owner

  @doc "The subset of `all/0` that `Render.carried_var/1` round-trips for an unsaved var."
  @spec carried() :: [atom()]
  def carried, do: @all -- @owner
end
