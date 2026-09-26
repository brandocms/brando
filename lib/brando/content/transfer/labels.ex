defmodule Brando.Content.Transfer.Labels do
  @moduledoc false
  use Gettext, backend: Brando.Gettext

  def field(name), do: label(to_string(name))

  @doc """
  The label an entry's form gives field `name` of `schema`, in the admin's
  language; the general label when the form has none.
  """
  def field(schema, name) do
    name = to_string(name)
    labels = form(schema)
    Map.get(labels, name) || Map.get(labels, String.replace_suffix(name, "_id", "")) || label(name)
  end

  @doc "The labels of `schema`'s form inputs, by field name, translated."
  def form(schema) do
    naming = schema.__naming__()
    domain = String.downcase("#{naming.domain}_#{naming.schema}")
    gettext = schema.__modules__().gettext

    for %{tabs: tabs} <- [schema.__form__()],
        tab <- tabs,
        fieldset <- tab.fields,
        input <- Map.get(fieldset, :fields, []),
        text = (Map.get(input, :opts) || [])[:label],
        is_binary(text),
        into: %{},
        do: {to_string(input.name), Gettext.dgettext(gettext, domain, text)}
  rescue
    _ -> %{}
  end

  def schema(schema) do
    naming = schema.__naming__()
    domain = String.downcase("#{naming.domain}_#{naming.schema}")
    Gettext.dgettext(schema.__modules__().gettext, domain, Brando.Blueprint.get_singular(schema))
  end

  def language("en", "English"), do: dgettext("content_transfer", "English")
  def language("no", _), do: dgettext("content_transfer", "Norwegian")
  def language(_, text), do: text

  defp label("parent"), do: dgettext("content_transfer", "Parent")
  defp label("categories"), do: dgettext("content_transfer", "Categories")
  defp label("uri"), do: dgettext("content_transfer", "URI")
  defp label("css_classes"), do: dgettext("content_transfer", "CSS classes")
  defp label("json_ld_type"), do: dgettext("content_transfer", "Structured data type")
  defp label("meta_title"), do: dgettext("content_transfer", "SEO title")
  defp label("meta_image"), do: dgettext("content_transfer", "Sharing image")
  defp label("meta_image_id"), do: dgettext("content_transfer", "Sharing image")
  defp label("listing_image"), do: dgettext("content_transfer", "Listing image")
  defp label("listing_image_id"), do: dgettext("content_transfer", "Listing image")
  defp label("meta_description"), do: dgettext("content_transfer", "SEO description")
  defp label("has_url"), do: dgettext("content_transfer", "Public URL")
  defp label("publish_at"), do: dgettext("content_transfer", "Publication date")
  defp label("sequence"), do: dgettext("content_transfer", "Order")
  defp label("title"), do: dgettext("content_transfer", "Title")
  defp label("name"), do: dgettext("content_transfer", "Name")
  defp label("language"), do: dgettext("content_transfer", "Language")
  defp label("status"), do: dgettext("content_transfer", "Status")
  defp label("key"), do: dgettext("content_transfer", "Key")
  defp label("parent_key"), do: dgettext("content_transfer", "Parent key")
  defp label("slug"), do: dgettext("content_transfer", "Slug")
  defp label("template"), do: dgettext("content_transfer", "Template")
  defp label("blocks"), do: dgettext("content_transfer", "Blocks")
  defp label("block"), do: dgettext("content_transfer", "Block")
  defp label("entry"), do: dgettext("content_transfer", "Entry")
  defp label("module"), do: dgettext("content_transfer", "Module")
  defp label("module_entry"), do: dgettext("content_transfer", "Module entry")
  defp label("table_template"), do: dgettext("content_transfer", "Table template")
  defp label("identifier"), do: dgettext("content_transfer", "Entry link")
  defp label("fragment"), do: dgettext("content_transfer", "Fragment")
  defp label("palette"), do: dgettext("content_transfer", "Palette")
  defp label("container"), do: dgettext("content_transfer", "Container")
  defp label("module_set"), do: dgettext("content_transfer", "Module collection")
  defp label("image"), do: dgettext("content_transfer", "Image")
  defp label("file"), do: dgettext("content_transfer", "File")
  defp label("video"), do: dgettext("content_transfer", "Video")
  defp label("gallery"), do: dgettext("content_transfer", "Gallery")
  defp label("markdown_source"), do: dgettext("content_transfer", "Markdown source")
  defp label("markdown_version"), do: dgettext("content_transfer", "Markdown version")
  defp label("vars"), do: dgettext("content_transfer", "Variables")
  defp label("refs"), do: dgettext("content_transfer", "References")
  defp label("rows"), do: dgettext("content_transfer", "Rows")
  defp label("description"), do: dgettext("content_transfer", "Description")
  defp label("value"), do: dgettext("content_transfer", "Value")
  defp label("value_boolean"), do: dgettext("content_transfer", "Value")
  defp label("value_datetime"), do: dgettext("content_transfer", "Date and time")
  defp label("value_date"), do: dgettext("content_transfer", "Date")
  defp label("value_text"), do: dgettext("content_transfer", "Text")
  defp label("type"), do: dgettext("content_transfer", "Type")
  defp label("label"), do: dgettext("content_transfer", "Label")
  defp label("link_text"), do: dgettext("content_transfer", "Link text")
  defp label("url"), do: dgettext("content_transfer", "URL")
  defp label("width"), do: dgettext("content_transfer", "Width")
  defp label("height"), do: dgettext("content_transfer", "Height")
  defp label("alt"), do: dgettext("content_transfer", "Alternative text")
  defp label("credits"), do: dgettext("content_transfer", "Credits")
  defp label("config_target"), do: dgettext("content_transfer", "Media configuration")
  defp label("gallery_objects"), do: dgettext("content_transfer", "Gallery items")
  defp label("palette_id"), do: dgettext("content_transfer", "Palette")
  defp label("link"), do: dgettext("content_transfer", "Link")
  defp label("text"), do: dgettext("content_transfer", "Text")
  defp label("header"), do: dgettext("content_transfer", "Heading")
  defp label("html"), do: dgettext("content_transfer", "HTML")
  defp label("svg"), do: dgettext("content_transfer", "SVG")
  defp label("slot"), do: dgettext("content_transfer", "Collection")
  defp label("media"), do: dgettext("content_transfer", "Media")
  defp label("table"), do: dgettext("content_transfer", "Table")
  defp label("datasource"), do: dgettext("content_transfer", "Datasource")
  defp label(name), do: Phoenix.Naming.humanize(name)
end
