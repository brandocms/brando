defmodule BrandoAdmin.Components.Form.LockedFields do
  @moduledoc """
  Entry fields the form shows a user but does not let them change, taken out
  of the params before the cast. The browser renders these read-only or not
  at all, so a value for one is a crafted request, not an edit:

    * for anyone but a superuser, a top-level input declared
      `readonly: :unless_superuser` or `disabled: :unless_superuser`, and every
      field of a `superuser` fieldset;
    * for everyone, a field the schema's `:creator` trait lists as `derived`
      (one a processing pipeline writes, such as an image's `sizes`) that the
      form has no input for.

  An image's `path` is one: the crop editor writes to it, so a path set from
  the form would write outside the media root.
  """

  alias Brando.Blueprint.Forms.Form
  alias Brando.Trait.Creator

  @doc "`params` without the fields `user` may not change in `schema`'s `blueprint` form."
  @spec drop(map() | nil, module(), struct() | nil, map() | atom()) :: map() | nil
  def drop(params, schema, %Form{} = blueprint, user) when is_map(params),
    do: Map.drop(params, schema |> params_for(fields(schema, blueprint, user)) |> Enum.map(&to_string/1))

  def drop(params, _schema, _blueprint, _user), do: params

  @doc "The field names `drop/4` takes out."
  @spec fields(module(), struct(), map() | atom()) :: [atom()]
  def fields(schema, %Form{tabs: tabs}, user) do
    fieldsets = for %{fields: fieldsets} <- tabs, %{fields: _} = fieldset <- fieldsets, do: fieldset
    inputs = Enum.flat_map(fieldsets, & &1.fields)
    derived = Creator.derived(schema) -- for(%{name: name} <- inputs, do: name)

    if superuser?(user) do
      derived
    else
      superuser_only = for %{superuser: true, fields: fields} <- fieldsets, %{name: name} <- fields, do: name
      unless_superuser = for %{name: name, opts: opts} <- inputs, unless_superuser?(opts), do: name
      Enum.uniq(derived ++ superuser_only ++ unless_superuser)
    end
  end

  # A media input (`input :cover, :image`) sends its foreign key, `cover_id`
  defp params_for(schema, fields) do
    Enum.flat_map(fields, fn field ->
      case schema.__schema__(:association, field) do
        %Ecto.Association.BelongsTo{owner_key: key} -> [field, key]
        _ -> [field]
      end
    end)
  end

  defp unless_superuser?(opts) when is_list(opts),
    do: Keyword.get(opts, :readonly) == :unless_superuser or Keyword.get(opts, :disabled) == :unless_superuser

  defp unless_superuser?(_opts), do: false

  defp superuser?(%{role: :superuser}), do: true
  defp superuser?(_user), do: false
end
