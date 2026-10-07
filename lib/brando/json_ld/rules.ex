defmodule Brando.JSONLD.Rules do
  @moduledoc """
  Google's required and recommended properties for the structured data types
  that earn a rich result, and the checks on their values.

  The rules are data: one entry per type, with the page they come from. A
  missing required property is an error: Google shows no rich result for the
  node. A missing recommended property is a warning, as are values Google
  can't read — a date that isn't ISO 8601, a relative URL where an absolute
  one is needed, an empty name, a duration that isn't ISO 8601, or a value
  outside the type's vocabulary (an availability, an employment type).

  A rule names a property, a dotted path through linked or nested nodes
  (`"author.name"`, followed through `@id` references), `{:any, paths}` when
  one of several will do, or `{:when, {property, value}, path}` for a
  property needed only when another has a value.

  Types without a rich result (`WebSite`, `WebPage`, `Service`) have no rules
  and are checked only for their values.
  """

  @type issue :: %{
          level: :error | :warning,
          property: String.t(),
          kind: :missing | :invalid_date | :relative_url | :empty | :invalid_duration | :invalid_value
        }

  @rules %{
    # https://developers.google.com/search/docs/appearance/structured-data/article
    "Article" => %{
      required: [],
      recommended: [
        "author",
        "author.name",
        {:any, ["author.url", "author.sameAs"]},
        "datePublished",
        "dateModified",
        "headline",
        "image"
      ]
    },
    # https://developers.google.com/search/docs/appearance/structured-data/product-snippet
    # https://developers.google.com/search/docs/appearance/structured-data/merchant-listing
    "Product" => %{
      required: ["name", {:any, ["offers", "review", "aggregateRating"]}],
      recommended: ["image", "description", "sku"]
    },
    # https://developers.google.com/search/docs/appearance/structured-data/merchant-listing#offer-details
    "Offer" => %{
      required: ["price", "priceCurrency"],
      recommended: ["availability"]
    },
    # https://developers.google.com/search/docs/appearance/structured-data/review-snippet#aggregated-rating-type-definition
    "AggregateRating" => %{
      required: ["ratingValue", {:any, ["ratingCount", "reviewCount"]}],
      recommended: []
    },
    # https://developers.google.com/search/docs/appearance/structured-data/review-snippet#review-properties
    # `itemReviewed` is the product or recipe for a review nested in one.
    "Review" => %{
      required: ["author", "author.name", "reviewRating", "reviewRating.ratingValue"],
      standalone_required: ["itemReviewed"],
      recommended: ["datePublished"]
    },
    # https://developers.google.com/search/docs/appearance/structured-data/review-snippet#rating
    "Rating" => %{
      required: ["ratingValue"],
      recommended: []
    },
    # https://developers.google.com/search/docs/appearance/structured-data/job-posting
    "JobPosting" => %{
      required: [
        "title",
        "description",
        "datePosted",
        "hiringOrganization",
        {:any, ["jobLocation", "jobLocationType"]},
        {:when, {"jobLocationType", "TELECOMMUTE"}, "applicantLocationRequirements"}
      ],
      recommended: ["validThrough", "employmentType", "baseSalary"]
    },
    # https://developers.google.com/search/docs/appearance/structured-data/recipe
    "Recipe" => %{
      required: ["name", "image"],
      recommended: [
        "author",
        "datePublished",
        "description",
        "recipeIngredient",
        "recipeInstructions",
        "recipeYield",
        "prepTime",
        "cookTime",
        "totalTime",
        "recipeCategory",
        "recipeCuisine",
        "keywords",
        "nutrition.calories",
        "aggregateRating",
        "video"
      ]
    },
    # https://developers.google.com/search/docs/appearance/structured-data/video
    "VideoObject" => %{
      required: ["name", "thumbnailUrl", "uploadDate"],
      recommended: ["description", "duration", {:any, ["contentUrl", "embedUrl"]}]
    },
    # https://developers.google.com/search/docs/appearance/structured-data/breadcrumb
    "BreadcrumbList" => %{
      required: ["itemListElement"],
      recommended: []
    },
    "ListItem" => %{
      required: ["position", "name"],
      recommended: []
    },
    # https://developers.google.com/search/docs/appearance/structured-data/organization
    "Organization" => %{
      required: [],
      recommended: ["name", "url", "logo", "description", "sameAs"]
    },
    # https://developers.google.com/search/docs/appearance/structured-data/local-business
    "LocalBusiness" => %{
      required: ["name", "address"],
      recommended: ["telephone", "url", "geo", "openingHoursSpecification", "priceRange"]
    },
    # https://developers.google.com/search/docs/appearance/structured-data/profile-page
    "ProfilePage" => %{
      required: ["mainEntity", "mainEntity.name"],
      recommended: ["mainEntity.image", "mainEntity.sameAs"]
    },
    # https://developers.google.com/search/docs/appearance/structured-data/profile-page
    # An author's own recommendations (url, sameAs) belong to the article.
    "Person" => %{
      required: ["name"],
      recommended: []
    },
    # https://developers.google.com/search/docs/appearance/structured-data/event
    "Event" => %{
      required: ["name", "startDate", "location"],
      recommended: ["description", "endDate", "eventStatus", "eventAttendanceMode", "image", "offers", "organizer"]
    }
  }

  # Subtypes read with their parent's rules.
  @aliases %{
    "NewsArticle" => "Article",
    "BlogPosting" => "Article",
    "ExhibitionEvent" => "Event",
    "Corporation" => "Organization",
    "NGO" => "Organization",
    "EducationalOrganization" => "Organization",
    "GovernmentOrganization" => "Organization",
    "MedicalOrganization" => "Organization",
    "SportsOrganization" => "Organization",
    "ProfessionalService" => "LocalBusiness",
    "Architect" => "LocalBusiness",
    "ArtGallery" => "LocalBusiness",
    "EmploymentAgency" => "LocalBusiness",
    "Restaurant" => "LocalBusiness"
  }

  @dates ~w(datePublished dateModified uploadDate datePosted validThrough startDate endDate priceValidUntil
            foundingDate)
  @urls ~w(url thumbnailUrl contentUrl embedUrl sameAs item mainEntityOfPage additionalType)
  @durations ~w(duration totalTime prepTime cookTime)
  @names ~w(name headline title)
  @numbers ~w(price ratingValue ratingCount reviewCount bestRating worstRating)

  @doc "The rules for `type`, following subtypes to their parent; `nil` for none."
  @spec for_type(String.t() | [String.t()] | nil) :: map() | nil
  def for_type([type | _]), do: for_type(type)
  def for_type(type) when is_binary(type), do: Map.get(@rules, Map.get(@aliases, type, type))
  def for_type(_type), do: nil

  @doc "Every type with rules, subtypes included."
  @spec types() :: [String.t()]
  def types, do: Enum.sort(Map.keys(@rules) ++ Map.keys(@aliases))

  @doc """
  The properties `type`'s rules name at the top level, required first, as
  `{property, :required | :recommended}`.
  """
  @spec properties(String.t() | nil, keyword()) :: [{String.t(), :required | :recommended}]
  def properties(type, opts \\ []) do
    case for_type(type) do
      nil ->
        []

      rules ->
        required = required(rules, opts) |> Enum.flat_map(&top_level/1) |> Enum.map(&{&1, :required})
        recommended = rules.recommended |> Enum.flat_map(&top_level/1) |> Enum.map(&{&1, :recommended})
        Enum.uniq_by(required ++ recommended, &elem(&1, 0))
    end
  end

  @doc """
  Checks `node`, a decoded JSON-LD node (string keys), against its type's
  rules and checks its values.

  ## Options

    * `:lookup` — a function from an `@id` to the graph's node with that id,
      so paths can be followed through references
    * `:standalone` — whether the node is a top-level entity rather than
      nested in another (default `true`)
    * `:skip_nested` — nested types that are checked as nodes of their own,
      and so are left out here
  """
  @spec validate(map(), keyword()) :: [issue()]
  def validate(node, opts \\ []) when is_map(node) do
    validate_node(node, "", opts)
  end

  defp validate_node(node, prefix, opts) do
    lookup = Keyword.get(opts, :lookup, fn _ -> nil end)

    rule_issues =
      case for_type(node["@type"]) do
        nil ->
          []

        rules ->
          missing(required(rules, opts), node, lookup, :error) ++
            missing(rules.recommended, node, lookup, :warning)
      end

    (rule_issues ++ value_issues(node) ++ nested_issues(node, opts))
    |> Enum.map(&%{&1 | property: prefix <> &1.property})
  end

  defp required(rules, opts) do
    if Keyword.get(opts, :standalone, true),
      do: rules.required ++ Map.get(rules, :standalone_required, []),
      else: rules.required
  end

  defp missing(rules, node, lookup, level) do
    for rule <- rules, not satisfied?(rule, node, lookup) do
      %{level: level, property: rule_label(rule), kind: :missing}
    end
  end

  defp satisfied?({:any, paths}, node, lookup), do: Enum.any?(paths, &satisfied?(&1, node, lookup))

  defp satisfied?({:when, {property, value}, path}, node, lookup),
    do: node[property] != value or satisfied?(path, node, lookup)

  defp satisfied?(path, node, lookup) when is_binary(path), do: present_at?(node, String.split(path, "."), lookup)

  defp present_at?(value, [], _lookup), do: present?(value)

  defp present_at?(list, keys, lookup) when is_list(list) and list != [],
    do: Enum.all?(list, &present_at?(&1, keys, lookup))

  defp present_at?(%{"@id" => id} = ref, keys, lookup) when map_size(ref) == 1 do
    case lookup.(id) do
      %{} = node -> present_at?(node, keys, lookup)
      _ -> false
    end
  end

  defp present_at?(%{} = node, [key | rest], lookup), do: present_at?(Map.get(node, key), rest, lookup)
  defp present_at?(_value, _keys, _lookup), do: false

  @doc "Whether a property's value counts as set."
  @spec present?(term()) :: boolean()
  def present?(nil), do: false
  def present?(""), do: false
  def present?([]), do: false
  def present?(value) when is_binary(value), do: String.trim(value) != ""
  def present?(%{} = map), do: map |> Map.drop(["@type", "@context"]) |> map_size() > 0
  def present?(_value), do: true

  defp rule_label({:any, paths}), do: Enum.join(paths, " | ")
  defp rule_label({:when, _condition, path}), do: path
  defp rule_label(path), do: path

  defp top_level({:any, paths}), do: [paths |> Enum.map(&first_key/1) |> Enum.uniq() |> Enum.join(" | ")]
  defp top_level({:when, _condition, path}), do: [first_key(path)]
  defp top_level(path), do: [first_key(path)]

  defp first_key(path), do: path |> String.split(".") |> hd()

  defp value_issues(node) do
    Enum.flat_map(node, fn {property, value} -> check_value(property, value, node) end)
  end

  defp check_value(property, values, node) when is_list(values) and property in @urls,
    do: values |> Enum.flat_map(&check_value(property, &1, node)) |> Enum.uniq()

  defp check_value(property, value, _node) when property in @dates and is_binary(value) do
    if iso_date?(value), do: [], else: [warning(property, :invalid_date)]
  end

  defp check_value(property, value, _node) when property in @urls and is_binary(value) do
    if absolute_url?(value), do: [], else: [warning(property, :relative_url)]
  end

  defp check_value(property, value, _node) when property in @durations and is_binary(value) do
    if Brando.JSONLD.iso_duration?(value), do: [], else: [warning(property, :invalid_duration)]
  end

  defp check_value(property, value, _node) when property in @names and is_binary(value) do
    if String.trim(value) == "", do: [warning(property, :empty)], else: []
  end

  defp check_value(property, value, _node) when property in @numbers and is_binary(value) do
    case Float.parse(value) do
      {_number, ""} -> []
      _ -> [warning(property, :invalid_value)]
    end
  end

  defp check_value("availability", value, _node) when is_binary(value) do
    available = Enum.map(Brando.JSONLD.Schema.Offer.availabilities(), &("https://schema.org/" <> &1))
    if value in available, do: [], else: [warning("availability", :invalid_value)]
  end

  defp check_value("employmentType", values, node) when is_list(values),
    do: values |> Enum.flat_map(&check_value("employmentType", &1, node)) |> Enum.uniq()

  defp check_value("employmentType", value, _node) when is_binary(value) do
    if value in Brando.JSONLD.Schema.JobPosting.employment_types(),
      do: [],
      else: [warning("employmentType", :invalid_value)]
  end

  defp check_value("jobLocationType", value, _node) when is_binary(value) do
    if value == "TELECOMMUTE", do: [], else: [warning("jobLocationType", :invalid_value)]
  end

  # An ImageObject's own URL, wherever the image sits.
  defp check_value(property, %{"@type" => "ImageObject", "url" => url}, _node) when is_binary(url) do
    if absolute_url?(url), do: [], else: [warning(property <> ".url", :relative_url)]
  end

  defp check_value(_property, _value, _node), do: []

  # Nested entities with rules of their own (an offer, a rating, the
  # breadcrumb's items) are checked in place, their properties prefixed with
  # the path to them. Types the caller shows as separate nodes are skipped.
  defp nested_issues(node, opts) do
    skip = Keyword.get(opts, :skip_nested, [])
    opts = Keyword.put(opts, :standalone, false)

    Enum.flat_map(node, fn
      {"@" <> _, _value} ->
        []

      {property, value} ->
        value
        |> List.wrap()
        |> Enum.with_index()
        |> Enum.flat_map(fn {item, index} ->
          nested_item_issues(item, nested_prefix(property, value, index), skip, opts)
        end)
    end)
  end

  defp nested_item_issues(%{"@type" => type} = item, prefix, skip, opts) do
    if type in skip, do: [], else: validate_node(item, prefix, opts)
  end

  defp nested_item_issues(_item, _prefix, _skip, _opts), do: []

  defp nested_prefix(property, value, index) when is_list(value), do: "#{property}[#{index}]."
  defp nested_prefix(property, _value, _index), do: property <> "."

  defp warning(property, kind), do: %{level: :warning, property: property, kind: kind}

  @doc "Whether `value` is an ISO 8601 date or date-time."
  @spec iso_date?(String.t()) :: boolean()
  def iso_date?(value) when is_binary(value) do
    match?({:ok, _, _}, DateTime.from_iso8601(value)) or match?({:ok, _}, NaiveDateTime.from_iso8601(value)) or
      match?({:ok, _}, Date.from_iso8601(value))
  end

  def iso_date?(_value), do: false

  @doc "Whether `value` is an absolute http(s) URL."
  @spec absolute_url?(String.t()) :: boolean()
  def absolute_url?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) and host != "" -> true
      _ -> false
    end
  end

  def absolute_url?(_value), do: false
end
