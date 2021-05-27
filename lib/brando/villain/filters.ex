defmodule Brando.Villain.Filters do
  use Liquex.Filter

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

  def date(%Date{} = value, format, _), do: Timex.format!(value, format, :strftime)

  def date(%DateTime{} = value, format, _) do
    value
    |> Timex.Timezone.convert(Brando.timezone())
    |> Timex.format!(format, :strftime)
  end

  def date(%NaiveDateTime{} = value, format, _), do: Timex.format!(value, format, :strftime)

  def date("now", format, context), do: date(DateTime.utc_now(), format, context)
  def date("today", format, context), do: date(Date.utc_today(), format, context)

  def date(value, format, _) when is_binary(value) do
    value
    |> Timex.parse!("{RFC3339z}")
    |> Timex.format!(format, :strftime)
  end

  def humanize(value, _) do
    value
    |> String.replace(["-", "_"], " ")
    |> String.capitalize()
  end

  @doc """
  Get key from image.

  It is prefered to use |size:"thumb" instead of this, but keeping these for backwards
  compatibility
  """
  def large(%Brando.Type.Image{} = img, _) do
    img
    |> Brando.HTML.picture_tag(key: :large, prefix: Brando.Utils.media_url())
    |> Phoenix.HTML.safe_to_string()
  end

  def large(img, _) do
    img
    |> Brando.HTML.picture_tag(key: :large)
    |> Phoenix.HTML.safe_to_string()
  end

  def xlarge(%Brando.Type.Image{} = img, _) do
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
  def size(%Brando.Type.Image{} = img, size, _) do
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
      when struct_type in [Brando.Type.Image, Brando.Images.Image] do
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
    Calendar.strftime(publish_at, format,
      month_names: fn month ->
        get_month_name(month, locale)
      end,
      day_of_week_names: fn day ->
        get_day_name(day, locale)
      end
    )
  end

  def publish_date(%{inserted_at: inserted_at}, format, locale, _) do
    Calendar.strftime(inserted_at, format,
      month_names: fn month ->
        get_month_name(month, locale)
      end,
      day_of_week_names: fn day ->
        get_day_name(day, locale)
      end
    )
  end

  @doc """
  Attempt to get `entry`'s absolute URL through blueprint
  """
  def absolute_url(%{__struct__: schema} = entry, _) do
    schema.__absolute_url__(entry)
  end

  @doc """
  Get src of image
  """
  def src(%Brando.Type.Image{} = img, size, _) do
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
  def markdown(%Brando.Sites.Global{data: %{"value" => str}}, opts), do: markdown(str, opts)

  def markdown(str, _) when is_binary(str) do
    str
    |> Brando.HTML.render_markdown()
    |> Phoenix.HTML.safe_to_string()
  end

  def get_month_name(month, locale) do
    Gettext.with_locale(locale, fn ->
      Gettext.dgettext(Brando.Gettext, "months", "month_#{month}")
    end)
  end

  def get_day_name(day, locale) do
    Gettext.with_locale(locale, fn ->
      Gettext.dgettext(Brando.Gettext, "days", "day_#{day}")
    end)
  end
end
