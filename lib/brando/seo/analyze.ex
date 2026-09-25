defmodule Brando.SEO.Analyze do
  @moduledoc """
  An AI critique of an entry's current meta title and description, read
  against the entry's own content.

  Advisory only: the reply is shown in the Content SEO tab and never written
  anywhere. It asks for at most three concrete problems, in the admin's
  language, and steers the model away from advice search engines have said
  they ignore — keyword density targets, llms.txt, rewriting for AI.
  """
  alias Brando.AI
  alias Brando.AI.Context
  alias Brando.SEO.Generate

  @content_length 1500
  @max_points 3

  @doc """
  Critiques the meta of entry `id` of `schema`. Returns up to three points.

  ## Options

    * `:language` — the language to answer in. Defaults to the admin locale.
    * `:queries` — the Google searches the page is shown for
      (`Brando.SEO.Analytics.top_queries/2`), which the critique then weighs
      the description against
  """
  @spec critique(module(), integer() | String.t(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def critique(schema, id, opts \\ []) do
    language = Keyword.get_lazy(opts, :language, fn -> Gettext.get_locale(Brando.Gettext) end)

    with {:ok, entry} <- Generate.fetch(schema, id),
         ai_opts = schema |> AI.field_ai_opts(:meta_description) |> Keyword.take([:model, :api_key]),
         {:ok, %{text: text}} <-
           AI.generate_text(prompt(schema, entry, language, Keyword.get(opts, :queries, [])), ai_opts) do
      case points(text) do
        [] -> {:error, :empty_response}
        points -> {:ok, points}
      end
    end
  end

  @doc "The prompt `critique/3` sends. Public so it can be read, and tested, without a request."
  @spec prompt(module(), map(), String.t() | atom(), [map()]) :: String.t()
  def prompt(schema, entry, language, queries \\ []) do
    """
    You review how one web page appears in search results. Reply in #{language_name(language)}.

    Judge the meta title and meta description against the page content below:
    - Does the description say what this page offers, rather than describing the site in general or another page?
    - Is it specific — concrete facts, names, places, numbers — rather than phrases that would fit any page?
    - Does it lead with what a searcher needs, instead of repeating the title?
    - Is it written for people, without keyword stuffing or stock phrases such as "discover", "learn more" or "in today's world"?
    - Does the content give a searcher enough to act on, or is it too thin to satisfy the search?

    Reply with at most #{@max_points} short bullet points, each starting with "- ", each naming one \
    concrete problem and how to fix it. If the title and description are good, reply with a single \
    bullet saying so. Do not suggest keyword density targets, llms.txt, or rewriting for AI crawlers.

    Page title: #{title(schema, entry)}
    Meta title: #{meta(schema, entry, :meta_title, "title")}
    Meta description: #{meta(schema, entry, :meta_description, "description")}
    Content: #{Context.block_text(entry, length: @content_length) || "(no body text)"}
    #{searches(queries)}\
    """
  end

  # Without its own meta field the page still shows what the blueprint's
  # meta_schema falls back to (usually the entry's title or intro); the model
  # should judge that, not be told the site fallback is used.
  defp meta(schema, entry, field, key) do
    case Map.get(entry, field) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        case schema |> Brando.Blueprint.Meta.extract_meta(entry, only: [key]) |> List.keyfind(key, 0) do
          {_, shown} when is_binary(shown) and shown != "" ->
            "(none — the page shows text taken from the entry: #{shown})"

          _ ->
            "(none — the site's fallback is used)"
        end
    end
  end

  # Given, the model can say whether the snippet answers what people are
  # actually looking for when Google shows them the page.
  defp searches([]), do: ""

  defp searches(queries) do
    lines =
      queries
      |> Enum.take(10)
      |> Enum.map_join("\n", fn query ->
        "- #{query.query} (#{query.impressions} impressions, #{query.clicks} clicks, position #{Float.round(query.position / 1, 1)})"
      end)

    """
    Google searches that showed this page recently — judge whether the title and description answer them:
    #{lines}
    """
  end

  @doc false
  def points(text) do
    text
    |> String.split(~r/\R/u)
    |> Enum.map(&String.replace(&1, ~r/^\s*(?:[-*•]|\d+[.)])\s*/u, ""))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(@max_points)
  end

  defp title(schema, entry) do
    Map.get(entry, :title) || Map.get(entry, :name) || Brando.Blueprint.get_singular(schema)
  end

  # The admin locale is one of the admin languages; content languages are the
  # fallback for a project that lists them only there.
  defp language_name(language) do
    language = to_string(language)

    case Enum.find(Brando.config(:admin_languages) || [], &(&1[:value] == language)) do
      nil -> AI.language_name(language)
      config -> config[:text] || AI.language_name(language)
    end
  end
end
