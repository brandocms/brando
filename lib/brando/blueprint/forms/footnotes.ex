defmodule Brando.Blueprint.Forms.Footnotes do
  @moduledoc """
  Explicit, field-local footnote configuration for Blueprint rich text.

  A configured input uses a dedicated ordinary blocks relation for its notes:

      relation :body_notes, :has_many, module: :blocks

      input :body, :rich_text,
        footnotes: [blocks: :body_notes, module_set: "Footnotes"]

  The form mounts that relation's editor outside the entry form. Its slots use
  the existing block save, revision, recovery and media machinery.
  """
  alias Brando.Blueprint.Forms

  def config(opts) do
    case Keyword.get(opts || [], :footnotes, false) do
      value when value in [nil, false] ->
        nil

      value when is_list(value) ->
        with blocks when is_atom(blocks) and not is_nil(blocks) <- Keyword.get(value, :blocks),
             set when is_binary(set) and set != "" <- Keyword.get(value, :module_set) do
          enabled = Keyword.get(value, :enabled, true)
          if enabled not in [true, false], do: invalid!()
          %{blocks: blocks, module_set: set, enabled: enabled}
        else
          _ -> invalid!()
        end

      _ ->
        invalid!()
    end
  end

  def fields(%{tabs: tabs}) do
    for tab <- tabs,
        fieldset <- tab.fields,
        %Forms.Input{type: :rich_text} = input <- fieldset.fields,
        config = config(input.opts),
        config != nil,
        into: %{},
        do: {input.name, config}
  end

  def fields(_), do: %{}

  def field(schema, name) do
    schema.__form__()
    |> fields()
    |> Enum.find_value(fn {field, config} ->
      if to_string(field) == to_string(name), do: Map.put(config, :field, field)
    end)
  end

  def mount_fields(form) do
    fields = fields(form)

    note_fields =
      fields
      |> Enum.group_by(fn {_field, config} -> config.blocks end)
      |> Enum.map(fn {blocks, fields} ->
        if Enum.any?(form.blocks, &(&1.name == blocks)) do
          raise ArgumentError, "#{blocks} is used for footnotes and must not also be mounted as a regular blocks editor"
        end

        %Forms.Input{name: blocks, type: :blocks, opts: [footnote_fields: Map.new(fields)]}
      end)

    # Nested forms need their own owner and relation. Reject accidental opt-in
    # there instead of presenting a toolbar that cannot save its notes.
    for tab <- form.tabs,
        fieldset <- tab.fields,
        %Forms.Subform{sub_fields: inputs} <- fieldset.fields,
        %Forms.Input{type: :rich_text} = input <- inputs,
        config(input.opts) != nil do
      raise ArgumentError, "Footnotes currently require a top-level Blueprint rich_text input (#{input.name})"
    end

    %{form | blocks: form.blocks ++ note_fields}
  end

  defp invalid! do
    raise ArgumentError,
          "Enable footnotes with footnotes: [blocks: :body_notes, module_set: \"Footnotes\"] and declare the :body_notes blocks relation"
  end
end
