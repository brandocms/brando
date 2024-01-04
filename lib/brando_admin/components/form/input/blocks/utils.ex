# TODO: REWRITE with new form logic?
defmodule BrandoAdmin.Components.Form.Input.Blocks.Utils do
  # use Phoenix.HTML

  def form_for_map(field, opts \\ []) do
    id = field.id
    name = field.name
    data = Map.get(field.form.source.data, field.name)
    params = Map.get(field.form.source.params || %{}, to_string(field.name), %{})

    %Phoenix.HTML.Form{
      source: field.form.source,
      impl: Phoenix.HTML.FormData.Ecto.Changeset,
      id: id,
      index: nil,
      name: to_string(name),
      errors: [],
      data: data,
      params: params,
      options: opts
    }
  end

  def form_for_map_value(field, opts \\ []) do
    id = field.id
    name = field.name
    data = Map.get(field.form.data, field.name)
    params = Map.get(field.form.params || %{}, to_string(field.name), %{})

    %Phoenix.HTML.Form{
      source: field.form.source,
      impl: Phoenix.HTML.FormData.Ecto.Changeset,
      id: id,
      index: nil,
      name: "#{to_string(name)}",
      errors: [],
      data: data,
      params: params,
      options: opts
    }
  end

  def inputs_for_blocks(field, opts \\ []) do
    to_form_multi(field.form.source, field, opts)
  end

  def inputs_for_poly(field, opts \\ []) do
    to_form_multi(field.form.source, field, opts)
  end

  def inputs_for_block(field, opts \\ []) do
    to_form_single(field.form.source, field, opts)
  end

  def to_form_single(%{action: parent_action} = source_changeset, field, options) do
    id = field.id
    name = field.field

    params = Map.get(source_changeset.params || %{}, to_string(name), %{})
    block = Ecto.Changeset.get_field(source_changeset, name)

    changeset =
      Ecto.Changeset.change(block)
      |> maybe_apply_action(parent_action)

    errors = get_errors(changeset)

    changeset = %Ecto.Changeset{
      changeset
      | action: parent_action,
        params: params,
        errors: errors,
        valid?: errors == []
    }

    %Phoenix.HTML.Form{
      source: changeset,
      impl: Phoenix.HTML.FormData.Ecto.Changeset,
      id: id,
      index: nil,
      name: field.name,
      errors: errors,
      data: block,
      params: params,
      options: options
    }
    |> List.wrap()
  end

  def to_form_multi(%{action: parent_action} = source_changeset, field, options) do
    id = field.id
    name = field.field

    params = Map.get(source_changeset.params || %{}, to_string(name), %{}) |> List.wrap()
    params = if params == [""], do: [%{}], else: params

    list_data = Ecto.Changeset.get_field(source_changeset, name) |> List.wrap()

    list_data
    |> Enum.with_index()
    |> Enum.map(fn
      {%{type: _type} = block, i} ->
        params = Enum.at(params, i) || %{}

        changeset =
          block
          |> Ecto.Changeset.change()
          |> maybe_apply_action(parent_action)

        errors = get_errors(changeset)

        changeset = %Ecto.Changeset{
          changeset
          | action: parent_action,
            params: params,
            errors: errors,
            valid?: errors == []
        }

        %Phoenix.HTML.Form{
          source: changeset,
          impl: Phoenix.HTML.FormData.Ecto.Changeset,
          id: id <> "_#{i}",
          index: i,
          name: to_string(field.name <> "[#{i}]"),
          errors: errors,
          data: block,
          params: params,
          options: options
        }

      {%Ecto.Changeset{} = changeset, i} ->
        errors = get_errors(changeset)

        %Phoenix.HTML.Form{
          source: changeset,
          impl: Phoenix.HTML.FormData.Ecto.Changeset,
          id: id <> "_#{i}",
          index: i,
          name: to_string(field.name <> "[#{i}]"),
          errors: errors,
          data: changeset.data,
          params: changeset.params,
          options: options
        }
    end)
  end

  # If the parent changeset had no action, we need to remove the action
  # from children changeset so we ignore all errors accordingly.
  defp maybe_apply_action(changeset, nil), do: %{changeset | action: nil}
  defp maybe_apply_action(changeset, _action), do: changeset

  defp get_errors(%{action: nil}), do: []
  defp get_errors(%{action: :ignore}), do: []
  defp get_errors(%{errors: errors}), do: errors
end
