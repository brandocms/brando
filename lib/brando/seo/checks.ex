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
  # Below this many words of body text a page gives search engines little to
  # rank and readers little reason to stay. Coverage floor, not a ranking
  # factor: a contact page may legitimately sit under it, hence a warning.
  @thin_content_words 300
  # A language version this much shorter than its longest sibling has likely
  # lost sections in translation; ratios between languages rarely differ by
  # more than a third.
  @parity_word_ratio 0.7
  @parity_min_words 150
  # Edits to one language version this long after another's suggest the
  # other was not brought along.
  @parity_stale_days 90
  # Alt text that names the file, or says only that it is a picture.
  @filename_alt ~r/(\.(jpe?g|png|gif|webp|avif|svg|heic)$)|^(img|image|dsc|photo|pxl)[-_ ]?\d+$/i
  @generic_alts ~w(image picture photo photograph img bilde foto illustrasjon illustration)
  # A first-page result clicked by fewer than one in a hundred searchers is
  # being passed over; below a hundred impressions the rate is noise.
  @ctr_min_impressions 100
  @ctr_max_position 10
  @ctr_floor 0.01

  @type ctx :: %{
          fallback_title: String.t() | nil,
          fallback_description: String.t() | nil,
          title_counts: %{String.t() => pos_integer()},
          description_counts: %{String.t() => pos_integer()},
          sitemap: MapSet.t() | nil,
          thin_content_words: pos_integer()
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
      in_sitemap(row, ctx),
      thin_content(row, ctx),
      heading_structure(row),
      image_alt(row),
      translation_parity(row)
    ] ++ if(ctx[:search_console?], do: [search_click_through(row)], else: [])
  end

  @doc """
  The word count under which an entry's body counts as thin.

      config :brando, Brando.SEO, thin_content_words: 300
  """
  @spec thin_content_words() :: pos_integer()
  def thin_content_words do
    :brando |> Application.get_env(Brando.SEO, []) |> Keyword.get(:thin_content_words, @thin_content_words)
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

  @doc """
  The page needs a title of its own. Most blueprints fall back from the meta
  title to the entry's title, which is exactly what a page should show; only
  the site-wide fallback title fails.
  """
  def meta_title_present(row) do
    cond do
      present?(row.meta_title) ->
        check(:meta_title_present, true, :normal, gettext("Meta title"), [])

      present?(row.shown_title) ->
        %Check{
          key: :meta_title_present,
          status: :pass,
          weight: :normal,
          label: gettext("Meta title"),
          value: gettext("from the entry")
        }

      true ->
        check(:meta_title_present, false, :normal, gettext("Meta title"),
          hint: gettext("Set a meta title; the site fallback is used otherwise.")
        )
    end
  end

  def meta_title_length(%{shown_title: title}) when title in [nil, ""],
    do: skip(:meta_title_length, :low, gettext("Meta title length"), gettext("There is no meta title to measure."))

  def meta_title_length(row) do
    length_check(:meta_title_length, row.shown_title, @title_range, gettext("Meta title length"))
  end

  @doc """
  A description written for search results passes. Text the blueprint takes
  from the entry instead (an intro, say) is a real description but not one
  written for a result, so it warns; only the site-wide fallback fails.
  """
  def meta_description_present(row) do
    cond do
      present?(row.meta_description) ->
        check(:meta_description_present, true, :critical, gettext("Meta description"), [])

      present?(row.shown_description) ->
        %Check{
          key: :meta_description_present,
          status: :warn,
          weight: :critical,
          label: gettext("Meta description"),
          value: gettext("from the entry"),
          hint:
            gettext("Search results show text taken from the entry; a description written for them usually does better.")
        }

      true ->
        check(:meta_description_present, false, :critical, gettext("Meta description"),
          hint: gettext("Write a meta description; search results show the site fallback otherwise.")
        )
    end
  end

  def meta_description_length(%{shown_description: desc}) when desc in [nil, ""],
    do:
      skip(
        :meta_description_length,
        :low,
        gettext("Meta description length"),
        gettext("There is no meta description to measure.")
      )

  def meta_description_length(row) do
    length_check(:meta_description_length, row.shown_description, @description_range, gettext("Meta description length"))
  end

  def meta_description_not_fallback(row, ctx) do
    fallback = normalize(ctx[:fallback_description])
    own = normalize(row.shown_description)
    status = if own && fallback && own == fallback, do: :fail, else: :pass

    %Check{
      key: :meta_description_not_fallback,
      status: if(is_nil(own), do: :skip, else: status),
      weight: :normal,
      label: gettext("Own description"),
      hint:
        if(is_nil(own),
          do: gettext("There is no meta description to compare with the site fallback."),
          else: gettext("This entry repeats the site fallback description; write one about this page.")
        )
    }
  end

  def meta_image(row) do
    check(:meta_image, row.has_meta_image or present?(row.cover), :normal, gettext("Sharing image"),
      hint: gettext("Add a meta image or a cover image so shares get a picture.")
    )
  end

  # Identical copy fails; a description that merely opens with the title
  # wastes the first words a search result shows, and only warns.
  def title_not_description(row) do
    title = normalize(row.shown_title)
    description = normalize(row.shown_description)

    {status, hint} =
      cond do
        is_nil(title) or is_nil(description) -> {:pass, nil}
        title == description -> {:fail, gettext("The meta title and description are identical.")}
        String.starts_with?(description, title) -> {:warn, gettext("The description opens by repeating the title.")}
        true -> {:pass, nil}
      end

    %Check{
      key: :title_not_description,
      status: status,
      weight: :low,
      label: gettext("Title differs from description"),
      hint: hint
    }
  end

  def duplicate_title(row, ctx),
    do:
      duplicate(
        :duplicate_title,
        row.shown_title,
        ctx.title_counts,
        gettext("Unique title"),
        gettext("There is no meta title to compare with other entries.")
      )

  def duplicate_description(row, ctx),
    do:
      duplicate(
        :duplicate_description,
        row.shown_description,
        ctx.description_counts,
        gettext("Unique description"),
        gettext("There is no meta description to compare with other entries.")
      )

  def url_resolves(row) do
    check(:url_resolves, present?(row.url), :critical, gettext("URL"),
      hint: gettext("The entry has no resolvable URL; check its slug and the blueprint's absolute_url.")
    )
  end

  def in_sitemap(_row, %{sitemap: nil}),
    do: skip(:in_sitemap, :normal, gettext("In sitemap"), gettext("No sitemap has been generated for this site yet."))

  def in_sitemap(row, %{sitemap: sitemap}) do
    check(:in_sitemap, present?(row.url) and MapSet.member?(sitemap, path(row.url)), :normal, gettext("In sitemap"),
      hint: gettext("Not in the generated sitemap. Check the sitemap module, or regenerate it.")
    )
  end

  @doc """
  Body text below `thin_content_words/0` warns; an entry whose blocks render
  no text at all fails. Skipped for schemas without block fields, where the
  audit has no body to count.
  """
  def thin_content(%{word_count: nil}, _ctx),
    do: skip(:thin_content, :normal, gettext("Content length"), no_blocks())

  def thin_content(row, ctx) do
    minimum = Map.get(ctx, :thin_content_words) || thin_content_words()

    status =
      cond do
        row.word_count == 0 -> :fail
        row.word_count < minimum -> :warn
        true -> :pass
      end

    %Check{
      key: :thin_content,
      status: status,
      weight: :normal,
      label: gettext("Content length"),
      hint: gettext("Thin content: aim for at least %{count} words of body text.", count: minimum),
      value: gettext("%{count} words", count: row.word_count)
    }
  end

  @doc """
  One H1 at most in the body — the page title is normally the template's
  H1 — and no skipped levels, counting from that title. Warns only: the
  template is out of sight, so this reads the content alone.
  """
  def heading_structure(%{headings: nil}),
    do: skip(:heading_structure, :low, gettext("Heading structure"), no_blocks())

  def heading_structure(%{headings: headings}) do
    h1s = Enum.count(headings, &(&1 == 1))
    skips = skipped_levels(headings)

    hints =
      Enum.reject(
        [
          h1s > 1 &&
            gettext("The content has %{count} H1 headings; a page should have one, usually its title.", count: h1s),
          skips != [] &&
            gettext("Heading levels skip from %{levels}.",
              levels: Enum.map_join(skips, ", ", fn {from, to} -> "H#{from} → H#{to}" end)
            )
        ],
        &(&1 == false)
      )

    %Check{
      key: :heading_structure,
      status: if(hints == [], do: :pass, else: :warn),
      weight: :low,
      label: gettext("Heading structure"),
      hint: if(hints != [], do: Enum.join(hints, " "))
    }
  end

  @doc """
  Every image in the body needs alt text that describes it: not empty, not
  a filename, not just "image".
  """
  def image_alt(%{image_alts: nil}), do: skip(:image_alt, :normal, gettext("Image descriptions"), no_blocks())

  def image_alt(%{image_alts: []}),
    do: skip(:image_alt, :normal, gettext("Image descriptions"), gettext("The content has no images."))

  def image_alt(%{image_alts: alts}) do
    missing = Enum.count(alts, &(not present?(&1)))
    poor = Enum.count(alts, &(present?(&1) and poor_alt?(&1)))
    total = length(alts)

    %Check{
      key: :image_alt,
      status: if(missing + poor == 0, do: :pass, else: :warn),
      weight: :normal,
      label: gettext("Image descriptions"),
      hint:
        gettext(
          "%{missing} of %{total} images have no alt text and %{poor} only a filename or a generic word. Describe them in the image library.",
          missing: missing,
          total: total,
          poor: poor
        ),
      value: if(missing + poor > 0, do: "#{missing + poor}/#{total}")
    }
  end

  @doc """
  Compares an entry with its published language versions: much shorter,
  fewer images, a different number of headings, or not edited for months
  after another version was.
  """
  def translation_parity(%{alternates: alternates}) when alternates in [nil, []],
    do:
      skip(
        :translation_parity,
        :normal,
        gettext("Language versions"),
        gettext("There are no other published language versions to compare with.")
      )

  def translation_parity(row) do
    hints = Enum.flat_map(row.alternates, &parity_issues(row, &1))

    %Check{
      key: :translation_parity,
      status: if(hints == [], do: :pass, else: :warn),
      weight: :normal,
      label: gettext("Language versions"),
      hint: if(hints != [], do: Enum.join(hints, " "))
    }
  end

  @doc """
  Search Console only: a page shown on Google's first page at least a
  hundred times, but clicked by under 1% of searchers. The title and
  description are what those searchers read, so that is where to look.
  """
  def search_click_through(%{traffic: %{impressions: impressions, ctr: ctr, position: position}})
      when impressions >= @ctr_min_impressions and position <= @ctr_max_position do
    %Check{
      key: :search_click_through,
      status: if(ctr < @ctr_floor, do: :warn, else: :pass),
      weight: :normal,
      label: gettext("Search click-through"),
      hint:
        gettext(
          "Shown in Google %{impressions} times at position %{position}, but clicked by %{ctr} of searchers. A title and description that match what people search for earn more clicks.",
          impressions: impressions,
          position: :erlang.float_to_binary(position / 1, decimals: 1),
          ctr: percent(ctr)
        ),
      value: percent(ctr)
    }
  end

  def search_click_through(_row) do
    skip(
      :search_click_through,
      :normal,
      gettext("Search click-through"),
      gettext("Needs at least %{count} impressions on Google's first page.", count: @ctr_min_impressions)
    )
  end

  @doc "A 0–1 rate as a percentage with one decimal."
  def percent(rate), do: :erlang.float_to_binary(rate * 100.0, decimals: 1) <> "%"

  defp parity_issues(row, alternate) do
    language = Brando.AI.language_name(alternate.language)
    other = alternate.stats

    [
      other && row.word_count && other.words >= @parity_min_words &&
        row.word_count < other.words * @parity_word_ratio &&
        gettext("Much shorter than the %{language} version (%{words} against %{other} words).",
          language: language,
          words: row.word_count,
          other: other.words
        ),
      other && row.image_alts && length(row.image_alts) < length(other.image_alts) &&
        gettext("%{count} fewer images than the %{language} version.",
          count: length(other.image_alts) - length(row.image_alts),
          language: language
        ),
      other && row.headings && abs(length(row.headings) - length(other.headings)) > 1 &&
        gettext("%{count} headings, against %{other} in the %{language} version.",
          count: length(row.headings),
          other: length(other.headings),
          language: language
        ),
      stale_days(row.edited_at, alternate.edited_at) > @parity_stale_days &&
        gettext("The %{language} version was edited %{days} days after this one.",
          language: language,
          days: stale_days(row.edited_at, alternate.edited_at)
        )
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp stale_days(%_{} = own, %_{} = other) do
    div(max(to_unix(other) - to_unix(own), 0), 86_400)
  end

  defp stale_days(_, _), do: 0

  defp to_unix(%DateTime{} = at), do: DateTime.to_unix(at)
  defp to_unix(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  # The template's title is the H1 the body continues from.
  defp skipped_levels(headings) do
    {skips, _} =
      Enum.reduce(headings, {[], 1}, fn level, {skips, previous} ->
        if level > previous + 1, do: {[{previous, level} | skips], level}, else: {skips, level}
      end)

    Enum.reverse(skips)
  end

  defp poor_alt?(alt) do
    alt = String.trim(alt)
    Regex.match?(@filename_alt, alt) or String.downcase(alt) in @generic_alts
  end

  defp duplicate(key, value, counts, label, missing) do
    case normalize(value) do
      nil ->
        skip(key, :normal, label, missing)

      normalized ->
        count = Map.get(counts, normalized, 1)

        %Check{
          key: key,
          status: if(count > 1, do: :fail, else: :pass),
          weight: :normal,
          label: label,
          hint: gettext("Shared with %{count} other entries in this language.", count: count - 1),
          # Only a shared value is worth a number; "1" beside a pass reads as a problem.
          value: if(count > 1, do: count)
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

  # A skipped check says why, or "Not checked" reads as something the audit
  # forgot rather than a check with nothing to look at.
  defp skip(key, weight, label, reason),
    do: %Check{key: key, status: :skip, weight: weight, label: label, hint: reason}

  defp no_blocks, do: gettext("This content type has no block content to read.")

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp path("http" <> _ = url), do: URI.parse(url).path || "/"
  defp path(path), do: path
end
