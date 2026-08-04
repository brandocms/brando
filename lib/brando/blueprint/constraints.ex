defmodule Brando.Blueprint.Constraints do
  @moduledoc """
  Logic for changeset constraints

  ## Foreign key constraints

  Foreign key constraints are automatically added to the changeset for
  any :belongs_to assocs.

  ## Other constraints

      - `min_length`
      - `max_length`
      - `length`
      - `format` - see `Ecto.Changeset.validate_format/4`
      - `acceptance` - see `Ecto.Changeset.validate_acceptance/3`
      - `confirmation` - see `Ecto.Changeset.validate_confirmation/3`
      - `one_of` - list of fields, at least one of which must have a value
      - `exactly_one_of` - list of fields, exactly one of which must have a value
      - `check` - database check constraint name(s) to translate into field errors

  ## One of

  Some entries are valid with either of two fields filled in, but not with
  neither — a listing that needs an image *or* a video, for instance. Neither
  field can be `required: true` on its own, since either alone is enough.

      assets do
        asset :listing_image, :image, constraints: [one_of: [:listing_image, :listing_video]]
        asset :listing_video, :video
      end

  The error is attached to the field carrying the constraint, so declare it on
  the one whose input should show the message. Assets are matched on either the
  association or its `_id` column, so a picked-but-unsaved asset counts as
  present. Add `one_of_message` to override the default wording.

  Use `exactly_one_of` when the fields are alternatives rather than a fallback
  chain — a media item holding an image *or* a video, never both:

      assets do
        asset :image, :image, constraints: [exactly_one_of: [:image, :video]]
        asset :video, :video
      end

  This is usually mirrored by a database check constraint. The constraint is the
  guarantee; this validation is the readable error in front of it, so a form
  reports the problem instead of raising `Ecto.ConstraintError` on insert.
  `exactly_one_of_message` overrides the wording.

  ## Check constraints

  A validation only covers writes that go through the changeset. Anything else —
  a race between two requests, a direct `Repo.insert` — still hits the database
  constraint, and an undeclared one raises `Ecto.ConstraintError` rather than
  returning an invalid changeset. Declare it to get a field error instead:

      asset :image, :image,
        constraints: [
          exactly_one_of: [:image, :video],
          check: [must_have_one_media_type: "requires either an image or a video"]
        ]

  The name must match the constraint in the database exactly. A bare atom (or a
  list of them) uses `check_message`, or `"is invalid"` if that is not set.

  ## Block field constraints

      - `require_blocks` - list of module classes that must be present in the block field

  ### Example

      relations do
        relation :blocks, :has_many,
          module: :blocks,
          constraints: [require_blocks: ["header"]]
      end

  This validates that at least one block using a module with class `"header"` is present
  when the block field is saved. Validation is skipped for drafts and when blocks are not
  being cast (i.e., when only other fields are being updated).
  """
  import Ecto.Changeset
  import Ecto.Query

  alias Brando.Blueprint.AssociationKey
  alias Brando.Blueprint.DatabaseIdentifier
  alias Brando.RuntimeConfig

  @content_module Module.concat(["Brando", "Content", "Module"])

  def run_validations(changeset, _module, attributes) do
    attributes
    |> Enum.filter(&Map.get(&1.opts, :constraints, false))
    |> Enum.reduce(changeset, fn
      %{opts: %{constraints: constraints}} = attr, new_changeset ->
        constraints_map = Map.new(constraints)

        Enum.reduce(constraints_map, new_changeset, fn constraint, validated_changeset ->
          run_validation(constraint, validated_changeset, attr)
        end)
    end)
  end

  def run_fk_constraints(changeset, _module, []), do: changeset

  def run_fk_constraints(changeset, module, relations) do
    if module.__schema__(:source) do
      relations
      |> Enum.filter(&(&1.type == :belongs_to))
      |> Enum.reduce(changeset, &add_foreign_key_constraint/2)
    else
      changeset
    end
  end

  defp add_foreign_key_constraint(relation, changeset) do
    field = AssociationKey.for(relation)

    foreign_key_constraint(
      changeset,
      field,
      foreign_key_constraint_opts(relation, changeset, field)
    )
  end

  defp foreign_key_constraint_opts(%{opts: %{constraint_name: constraint_name}}, _changeset, _field),
    do: [name: DatabaseIdentifier.normalize(constraint_name)]

  defp foreign_key_constraint_opts(
         _relation,
         %Ecto.Changeset{data: %{__meta__: %{source: source}, __struct__: schema}},
         field
       )
       when is_binary(source) do
    field_source = schema.__schema__(:field_source, field) || field
    [name: DatabaseIdentifier.foreign_key_name(source, field_source)]
  end

  defp foreign_key_constraint_opts(_relation, _changeset, _field), do: []

  defp run_validation({:min_length, length}, validated_changeset, %{name: name, type: :entries}) do
    validate_length(validated_changeset, name, min: length)
  end

  defp run_validation({:min_length, min_length}, validated_changeset, %{name: name}),
    do: validate_length(validated_changeset, name, min: min_length)

  defp run_validation({:max_length, length}, validated_changeset, %{name: name, type: :entries}) do
    validate_length(validated_changeset, name, max: length)
  end

  defp run_validation({:max_length, max_length}, validated_changeset, %{name: name}),
    do: validate_length(validated_changeset, name, max: max_length)

  defp run_validation({:length, length}, validated_changeset, %{name: name, type: :entries}) do
    validate_length(validated_changeset, name, is: length)
  end

  defp run_validation({:length, length}, validated_changeset, %{name: name}),
    do: validate_length(validated_changeset, name, is: length)

  defp run_validation({:format, format}, validated_changeset, %{name: name}),
    do: validate_format(validated_changeset, name, format)

  defp run_validation({:acceptance, true}, validated_changeset, %{name: name}),
    do: validate_acceptance(validated_changeset, name)

  defp run_validation({:confirmation, true}, validated_changeset, %{name: name}),
    do: validate_confirmation(validated_changeset, name)

  defp run_validation({:one_of, fields}, changeset, %{name: name} = field_or_asset) do
    if Enum.any?(fields, &value_present?(changeset, &1)) do
      changeset
    else
      message = constraint_message(field_or_asset, :one_of_message, "requires one of: %{fields}")

      add_group_error(changeset, fields, name, message,
        validation: :one_of,
        one_of: fields,
        fields: field_list(fields)
      )
    end
  end

  defp run_validation({:exactly_one_of, fields}, changeset, %{name: name} = field_or_asset) do
    case Enum.count(fields, &value_present?(changeset, &1)) do
      1 ->
        changeset

      count ->
        message =
          constraint_message(
            field_or_asset,
            :exactly_one_of_message,
            "requires exactly one of: %{fields}"
          )

        add_group_error(changeset, fields, name, message,
          validation: :exactly_one_of,
          exactly_one_of: fields,
          present: count,
          fields: field_list(fields)
        )
    end
  end

  defp run_validation({:check, checks}, changeset, %{name: field} = field_or_asset) do
    default = constraint_message(field_or_asset, :check_message, "is invalid")

    checks
    |> normalize_checks(default)
    |> Enum.reduce(changeset, fn {constraint_name, message}, validated_changeset ->
      check_constraint(validated_changeset, field, name: constraint_name, message: message)
    end)
  end

  # Carried alongside the constraint they belong to; consumed there, not
  # constraints of their own.
  defp run_validation({:one_of_message, _message}, changeset, _field_or_asset), do: changeset

  defp run_validation({:exactly_one_of_message, _message}, changeset, _field_or_asset), do: changeset

  defp run_validation({:check_message, _message}, changeset, _field_or_asset), do: changeset

  defp run_validation({:require_blocks, required_classes}, changeset, %{name: name, opts: %{module: :blocks}}) do
    # Skip validation for drafts
    if Ecto.Changeset.get_field(changeset, :status) == :draft do
      changeset
    else
      assoc_field = :"entry_#{name}"
      validate_required_blocks(changeset, assoc_field, required_classes)
    end
  end

  # A group constraint is about the set, not one member of it, so the error goes
  # on every field involved — an editor looking at the video input should see why
  # it is flagged, not just the image input that happens to declare the rule.
  #
  # An asset is two things in the form: the association and the `<field>_id`
  # column. The form reads both the label's failed state and — via used_input? —
  # the message from the id, so that is where the error goes. Attaching to both
  # would list the field twice in the "fields marked invalid" summary.
  defp add_group_error(changeset, fields, declared_on, message, opts) do
    fields
    |> Enum.uniq()
    |> List.insert_at(-1, declared_on)
    |> Enum.uniq()
    |> Enum.reduce(changeset, fn field, acc ->
      add_error(acc, error_key(changeset, field), message, opts)
    end)
  end

  defp error_key(changeset, field) do
    relation_key = :"#{field}_id"
    if Map.has_key?(changeset.data, relation_key), do: relation_key, else: field
  end

  # `check: :name`, `check: [:a, :b]`, and `check: [name: "message"]` are all
  # accepted; the first two fall back to the shared `check_message`.
  defp normalize_checks(checks, default) when is_atom(checks), do: [{checks, default}]

  defp normalize_checks(checks, default) when is_list(checks) do
    if Keyword.keyword?(checks) do
      Enum.map(checks, fn {name, message} -> {name, message || default} end)
    else
      Enum.map(checks, &{&1, default})
    end
  end

  # Message overrides are declared alongside the constraint they belong to —
  # `constraints: [one_of: [...], one_of_message: "..."]` — so they are read back
  # out of the same keyword list rather than from the field's top-level options.
  defp constraint_message(field_or_asset, key, default) do
    field_or_asset
    |> Map.get(:opts, %{})
    |> Map.get(:constraints, [])
    |> Keyword.get(key, default)
  end

  # Interpolated into `%{fields}` the way Ecto messages carry `%{count}`. The
  # field names are the fallback; a form that knows the blueprint replaces them
  # with the inputs' labels before translating.
  defp field_list(fields), do: Enum.map_join(fields, ", ", &to_string/1)

  # An asset lives in the changeset as both an association and an `_id` column,
  # and which one is populated depends on how it was set — a picker writes the
  # id, an upload puts the struct. Either counts as present.
  defp value_present?(changeset, field) do
    present?(field_value(changeset, field)) or present?(field_value(changeset, :"#{field}_id"))
  end

  defp field_value(changeset, field) do
    if Map.has_key?(changeset.data, field), do: get_field(changeset, field)
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?([]), do: false
  defp present?(%Ecto.Association.NotLoaded{}), do: false
  defp present?(_value), do: true

  defp validate_required_blocks(changeset, assoc_field, required_classes) do
    case Ecto.Changeset.get_change(changeset, assoc_field) do
      nil ->
        # Blocks not being changed, skip validation
        changeset

      entry_block_changesets ->
        entry_block_changesets
        |> extract_block_module_ids()
        |> validate_required_modules(changeset, assoc_field, required_classes)
    end
  end

  defp validate_required_modules([], changeset, assoc_field, required_classes) when required_classes != [] do
    Enum.reduce(required_classes, changeset, fn required_class, validated_changeset ->
      add_required_block_error(validated_changeset, assoc_field, required_class)
    end)
  end

  defp validate_required_modules(module_ids, changeset, assoc_field, required_classes) do
    content_module = @content_module

    classes =
      RuntimeConfig.get(:repo_module).all(
        from module in content_module,
          where: module.id in ^module_ids,
          select: module.class
      )

    Enum.reduce(required_classes, changeset, fn required_class, validated_changeset ->
      validate_required_class(validated_changeset, assoc_field, required_class, classes)
    end)
  end

  defp validate_required_class(changeset, assoc_field, required_class, classes) do
    if required_class in classes do
      changeset
    else
      add_required_block_error(changeset, assoc_field, required_class)
    end
  end

  defp add_required_block_error(changeset, assoc_field, required_class) do
    add_error(changeset, assoc_field, "is missing required block: %{class}",
      class: required_class,
      validation: :require_blocks
    )
  end

  defp extract_block_module_ids(entry_block_changesets) do
    entry_block_changesets
    |> Enum.reject(&(&1.action == :delete))
    |> Enum.map(fn eb_cs ->
      case Ecto.Changeset.get_field(eb_cs, :block) do
        %Ecto.Association.NotLoaded{} -> nil
        nil -> nil
        %{active: false} -> nil
        %{module_id: module_id} -> module_id
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
