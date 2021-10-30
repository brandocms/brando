defmodule Brando.Villain.Filters do
  use Liquex.Filter
  alias Brando.Utils

  @doc """
  Converts `value` timestamp into another date `format`.
  The format for this syntax is the same as strftime. The input uses the same format as Ruby’s Time.parse.
  ## Examples
      iex> Brando.Lexer.Filter.date(~D[2000-01-01], "%m/%d/%Y", %{})
      "01/01/2000"
      iex> Brando.Lexer.Filter.date(~N[2020-07-06 15:00:00.000000], "%m/%d/%Y", %{})
      "07/06/2020"
      iex> Brando.Lexer.Filter.date(~U[2020-07-06 15:00:00.000000Z], "%m/%d/%Y", %{})
      "07/06/2020"
  """

  def date(%Date{} = value, format, _), do: Utils.Datetime.format_datetime(value, format, nil)

  def date(%DateTime{} = value, format, _) do
    value
    |> DateTime.shift_zone!(Brando.timezone())
    |> Utils.Datetime.format_datetime(format, nil)
  end

  def date(%NaiveDateTime{} = value, format, _),
    do: Utils.Datetime.format_datetime(value, format, nil)

  def date("now", format, context), do: date(DateTime.utc_now(), format, context)
  def date("today", format, context), do: date(Date.utc_today(), format, context)

  def date(value, format, _) when is_binary(value) do
    value
    |> DateTime.from_iso8601()
    |> Utils.Datetime.format_datetime(format, nil)
  end

  # {{ entry.inserted_at | date:"%A","nb_NO" }}
  def date(%DateTime{} = value, format, locale, _) do
    Utils.Datetime.format_datetime(value, format, locale)
  end

  def date(value, format, locale, _) do
    Utils.Datetime.format_datetime(value, format, locale)
  end

  def humanize(value, _) do
    Brando.Utils.humanize(value)
  end

  @doc """
  Get key from image.

  It is prefered to use |size:"thumb" instead of this, but keeping these for backwards
  compatibility
  """
  def large(%Brando.Images.Image{} = img, _) do
    img
    |> Brando.HTML.picture_tag(key: :large, prefix: Brando.Utils.media_url())
    |> Phoenix.HTML.safe_to_string()
  end

  def large(img, _) do
    img
    |> Brando.HTML.picture_tag(key: :large)
    |> Phoenix.HTML.safe_to_string()
  end

  def xlarge(%Brando.Images.Image{} = img, _) do
    img
    |> Brando.HTML.picture_tag(key: :xlarge, prefix: Brando.Utils.media_url())
    |> Phoenix.HTML.safe_to_string()
  end

  def xlarge(img, _) do
    img
    |> Brando.HTML.picture_tag(key: :xlarge)
    |> Phoenix.HTML.safe_to_string()
  end

  @doc """
  Get sized version of image
  """
  def size(%Brando.Images.Image{} = img, size, _) do
    img
    |> Brando.HTML.picture_tag(key: size, prefix: Brando.Utils.media_url())
    |> Phoenix.HTML.safe_to_string()
  end

  def size(img, size, _) do
    img
    |> Brando.HTML.picture_tag(key: size)
    |> Phoenix.HTML.safe_to_string()
  end

  @doc """
  Get srcset picture of image

  {{ entry.cover|srcset:"Attivo.Team.Employee:cover" }}
  """
  def srcset(%struct_type{} = img, srcset, _)
      when struct_type in [Brando.Images.Image] do
    img
    |> Brando.HTML.picture_tag(
      placeholder: :svg,
      lazyload: true,
      srcset: srcset,
      prefix: Brando.Utils.media_url()
    )
    |> Phoenix.HTML.safe_to_string()
  end

  def srcset(img, srcset, _) do
    [module_string, field_string] = String.split(srcset, ":")
    module = Module.concat([module_string])
    field = String.to_existing_atom(field_string)

    img
    |> Brando.HTML.picture_tag(
      placeholder: :svg,
      lazyload: true,
      srcset: {module, field}
    )
    |> Phoenix.HTML.safe_to_string()
  end

  @doc """
  Get entry publication date by publish_at OR inserted_at
  """
  def publish_date(%{publish_at: publish_at}, format, locale, _)
      when not is_nil(publish_at) do
    Utils.Datetime.format_datetime(publish_at, format, locale)
  end

  def publish_date(%{inserted_at: inserted_at}, format, locale, _) do
    Utils.Datetime.format_datetime(inserted_at, format, locale)
  end

  @doc """
  Attempt to get `entry`'s absolute URL through blueprint
  """
  def absolute_url(%{__struct__: schema} = entry, _) do
    schema.__absolute_url__(entry)
  end

  def schema(%{__struct__: schema}, _) do
    to_string(schema)
  end

  def schema(_, _) do
    nil
  end

  @doc """
  Get src of image
  """
  def src(%Brando.Images.Image{} = img, size, _) do
    Brando.Utils.img_url(img, size, prefix: Brando.Utils.media_url())
  end

  def src(img, size, _) do
    Brando.Utils.img_url(img, size)
  end

  def orientation(value, _), do: Brando.Images.get_image_orientation(value)

  @doc """
  Converts from markdown
  ## Examples
      iex> Brando.Lexer.Filter.markdown("this is a **string**", %{}) |> String.trim("\\n")
      "<p>this is a <strong>string</strong></p>"
  """
  def markdown(%{value: str}, opts), do: markdown(str, opts)

  def markdown(str, _) when is_binary(str) do
    str
    |> Brando.HTML.render_markdown()
    |> Phoenix.HTML.safe_to_string()
  end
end
