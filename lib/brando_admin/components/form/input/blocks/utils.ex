defmodule BrandoAdmin.Components.Form.Input.Blocks.Utils do
  use Phoenix.HTML

  def form_for_map(form, field, opts \\ []) do
    id = to_string(form.id <> "_#{field}")
    name = to_string(form.name <> "[#{field}]")
    data = Map.get(form.source.data, field)
    params = Map.get(form.source.params || %{}, to_string(field), %{})

    %Phoenix.HTML.Form{
      source: form.source,
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

  def form_for_map_value(form, field, opts \\ []) do
    id = to_string(form.id <> "_#{field}")
    name = to_string(form.name <> "[#{field}]")
    data = Map.get(form.data, field)

    params = Map.get(form.params || %{}, to_string(field), %{})

    require Logger
    Logger.error(inspect(form.params, pretty: true))
    Logger.error(inspect(form.source.params, pretty: true))

    %Phoenix.HTML.Form{
      source: form.source,
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

  def inputs_for_blocks(form, field, opts \\ []) do
    to_form_multi(form.source, form, field, opts)
  end

  def inputs_for_poly(form, field, opts \\ []) do
    to_form_multi(form.source, form, field, opts)
  end

  def inputs_for_block(form, field, opts \\ []) do
    to_form_single(form.source, form, field, opts)
  end

  def to_form_single(%{action: parent_action} = source_changeset, form, field, options) do
    id = to_string(form.id <> "_#{field}")
    name = to_string(form.name <> "[#{field}]")

    params = Map.get(source_changeset.params || %{}, to_string(field), %{})
    block = Ecto.Changeset.get_field(source_changeset, field)

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
      name: to_string(name),
      errors: errors,
      data: block,
      params: params,
      options: options
    }
    |> List.wrap()
  end

  def to_form_multi(%{action: parent_action} = source_changeset, form, field, options) do
    id = to_string(form.id <> "_#{field}")
    name = to_string(form.name <> "[#{field}]")

    params = Map.get(source_changeset.params || %{}, to_string(field), %{}) |> List.wrap()
    list_data = Ecto.Changeset.get_field(source_changeset, field) |> List.wrap()

    list_data
    |> Enum.with_index()
    |> Enum.map(fn
      {%{type: _type} = block, i} ->
        params = Enum.at(params, i) || %{}

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
          id: id <> "_#{i}",
          index: i,
          name: to_string(name <> "[#{i}]"),
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
          name: to_string(name <> "[#{i}]"),
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
