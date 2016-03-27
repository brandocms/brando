defmodule Brando.Form.Fields.Utils do
  @moduledoc """
  Utilities for form fields.
  """
  @doc """
  Prepend `html` to `field`'s html
  """
  def prepend_html(field, html) do
    html = is_list(html) && Enum.join(html, "") || html
    Map.put(field, :html, Enum.join([html, field.html], ""))
  end

  @doc """
  Append `html` to `field`'s html
  """
  def append_html(field, html) do
    html = is_list(html) && Enum.join(html, "") || html
    Map.put(field, :html, Enum.join([field.html, html], ""))
  end

  @doc """
  Set `field`'s html to `html`
  """
  def set_html(field, html) do
    Map.put(field, :html, Enum.join(html, ""))
  end

  @doc """
  Put `key` and `value` in `field`'s :opts
  """
  def put_in_opts(field, key, value) do
    opts =
      field.opts
      |> Map.put(key, value)

    field
    |> Map.put(:opts, opts)
  end

  @doc """
  Delete `key` from `field`'s :opts
  """
  def delete_in_opts(field, key) do
    opts =
      field.opts
      |> Map.delete(key)

    field
    |> Map.put(:opts, opts)
  end

  @doc """
  Put `key` and `value` in `field`
  """
  def put_in_field(field, key, value) do
    field
    |> Map.put(key, value)
  end

  @doc """
  Delete `key` in `field`
  """
  def delete_in_field(field, key) do
    field
    |> Map.delete(key)
  end
end
