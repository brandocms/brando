defmodule Brando.Form.Fields.Utils do
  def prepend_html(field, html) do
    html = is_list(html) && Enum.join(html, "") || html
    Map.put(field, :html, Enum.join([html, field.html], ""))
  end

  def append_html(field, html) do
    html = is_list(html) && Enum.join(html, "") || html
    Map.put(field, :html, Enum.join([field.html, html], ""))
  end

  def set_html(field, html) do
    Map.put(field, :html, Enum.join(html, ""))
  end

  def put_in_opts(field, key, value) do
    opts =
      field.opts
      |> Map.put(key, value)

    field
    |> Map.put(:opts, opts)
  end

  def delete_in_opts(field, key) do
    opts =
      field.opts
      |> Map.delete(key)

    field
    |> Map.put(:opts, opts)
  end

  def put_in_field(field, key, value) do
    field
    |> Map.put(key, value)
  end

  def delete_in_field(field, key) do
    field
    |> Map.delete(key)
  end
end
