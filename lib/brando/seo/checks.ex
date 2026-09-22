defmodule Brando.SEO.Checks do
  @moduledoc """
  The built-in content SEO checks.

  Each check is a pure function of an audit row and the audit context (site
  fallbacks, duplicate indexes, sitemap URLs). Thresholds follow what search
  engines actually display: titles are cut around 60 characters, descriptions
  around 155–160.
  """
  use Gettext, backend: Brando.Gettext

  alias Brando.SEO.Audit.Row
  alias Brando.SEO.Check

  @title_range 30..60
  @description_range 120..160

  @type ctx :: %{
          fallback_title: String.t() | nil,
          fallback_description: String.t() | nil,
          title_counts: %{String.t() => pos_integer()},
          description_counts: %{String.t() => pos_integer()},
          sitemap: MapSet.t() | nil
        }

  @doc "Runs every built-in check for `row`."
  @spec run(Row.t(), ctx()) :: [Check.t()]
  def run(%Row{} = row, ctx) do
    [
      meta_title_present(row),
      meta_title_length(row),
      meta_description_present(row),
      meta_description_length(row),
      meta_description_not_fallback(row, ctx),
      meta_image(row),
      title_not_description(row),
      duplicate_title(row, ctx),
      duplicate_description(row, ctx),
      url_resolves(row),
      in_sitemap(row, ctx)
    ]
  end

  @doc "Normalises a meta value for duplicate detection."
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    case value |> String.downcase() |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> nil
      normalized -> normalized
    end
  end

  def meta_title_present(row) do
    check(:meta_title_present, present?(row.meta_title), :normal, gettext("Meta title"),
      hint: gettext("Set a meta title; the site fallback is used otherwise.")
    )
  end

  def meta_title_length(%{meta_title: title}) when title in [nil, ""],
    do: skip(:meta_title_length, :low, gettext("Meta title length"))

  def meta_title_length(row) do
    length_check(:meta_title_length, row.meta_title, @title_range, gettext("Meta title length"))
  end

  def meta_description_present(row) do
    check(:meta_description_present, present?(row.meta_description), :critical, gettext("Meta description"),
      hint: gettext("Write a meta description; search results show the site fallback otherwise.")
    )
  end

  def meta_description_length(%{meta_description: desc}) when desc in [nil, ""],
    do: skip(:meta_description_length, :low, gettext("Meta description length"))

  def meta_description_length(row) do
    length_check(:meta_description_length, row.meta_description, @description_range, gettext("Meta description length"))
  end

  def meta_description_not_fallback(row, ctx) do
    fallback = normalize(ctx[:fallback_description])
    own = normalize(row.meta_description)
    status = if own && fallback && own == fallback, do: :fail, else: :pass

    %Check{
      key: :meta_description_not_fallback,
      status: if(is_nil(own), do: :skip, else: status),
      weight: :normal,
      label: gettext("Own description"),
      hint: gettext("This entry repeats the site fallback description; write one about this page.")
    }
  end

  def meta_image(row) do
    check(:meta_image, row.has_meta_image or present?(row.cover), :normal, gettext("Sharing image"),
      hint: gettext("Add a meta image or a cover image so shares get a picture.")
    )
  end

  def title_not_description(row) do
    same? = present?(row.meta_title) and normalize(row.meta_title) == normalize(row.meta_description)

    check(:title_not_description, not same?, :low, gettext("Title differs from description"),
      hint: gettext("The meta title and description are identical.")
    )
  end

  def duplicate_title(row, ctx),
    do: duplicate(:duplicate_title, row.meta_title, ctx.title_counts, gettext("Unique title"))

  def duplicate_description(row, ctx),
    do: duplicate(:duplicate_description, row.meta_description, ctx.description_counts, gettext("Unique description"))

  def url_resolves(row) do
    check(:url_resolves, present?(row.url), :critical, gettext("URL"),
      hint: gettext("The entry has no resolvable URL; check its slug and the blueprint's absolute_url.")
    )
  end

  def in_sitemap(_row, %{sitemap: nil}), do: skip(:in_sitemap, :normal, gettext("In sitemap"))

  def in_sitemap(row, %{sitemap: sitemap}) do
    check(:in_sitemap, present?(row.url) and MapSet.member?(sitemap, path(row.url)), :normal, gettext("In sitemap"),
      hint: gettext("Not in the generated sitemap. Check the sitemap module, or regenerate it.")
    )
  end

  defp duplicate(key, value, counts, label) do
    case normalize(value) do
      nil ->
        skip(key, :normal, label)

      normalized ->
        count = Map.get(counts, normalized, 1)

        %Check{
          key: key,
          status: if(count > 1, do: :fail, else: :pass),
          weight: :normal,
          label: label,
          hint: gettext("Shared with %{count} other entries in this language.", count: count - 1),
          value: count
        }
    end
  end

  defp length_check(key, value, range, label) do
    length = String.length(String.trim(value))
    status = if length in range, do: :pass, else: :warn

    %Check{
      key: key,
      status: status,
      weight: :low,
      label: label,
      hint: gettext("Aim for %{min}–%{max} characters.", min: range.first, max: range.last),
      value: length
    }
  end

  defp check(key, ok?, weight, label, opts) do
    %Check{key: key, status: if(ok?, do: :pass, else: :fail), weight: weight, label: label, hint: opts[:hint]}
  end

  defp skip(key, weight, label), do: %Check{key: key, status: :skip, weight: weight, label: label}

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp path("http" <> _ = url), do: URI.parse(url).path || "/"
  defp path(path), do: path
end
