defmodule Brando.SEO.Robots do
  @moduledoc """
  Builds the site's `robots.txt` from the SEO settings (`Brando.Sites.SEO`).

  The text is the editors' own robots text, then a generated block for the AI
  crawler policy, then the sitemap. The generated block sits between marker
  comments and is only ever composed at request time, so the editors' lines
  are never rewritten. A pasted copy of an earlier generated block is dropped
  from the editors' text, so the policy is not written twice.

  The policy is stored in the SEO entry's `crawler_policy`:

      %{"crawlers" => %{"GPTBot" => "block"}, "ai_train" => "no"}

  Crawlers not named are allowed. Nothing is generated until a crawler is
  blocked or a training preference is chosen, so a site that never opens the
  setting serves the robots text it had before.

  With a policy, the block ends with a [Content Signals](https://contentsignals.org)
  line for every crawler: `search=yes` (traditional search crawlers are never
  blocked here), `ai-input` from the AI search and user-fetch crawlers (`no`
  only when every one of them is blocked) and `ai-train` from its own setting,
  left out when there is no preference.
  """
  alias Brando.SEO.Crawlers

  @begin_marker "# BEGIN Brando AI crawler policy"
  @end_marker "# END Brando AI crawler policy"

  @default_robots """
  User-agent: *
  Disallow: /admin/
  """

  @content_signals_policy """
  # As a condition of accessing this website, you agree to
  # abide by the following content signals:

  # (a)  If a content-signal = yes, you may collect content
  # for the corresponding use.
  # (b)  If a content-signal = no, you may not collect content
  # for the corresponding use.
  # (c)  If the website operator does not include a content
  # signal for a corresponding use, the website operator
  # neither grants nor restricts permission via content signal
  # with respect to the corresponding use.

  # The content signals and their meanings are:

  # search: building a search index and providing search
  # results (e.g., returning hyperlinks and short excerpts
  # from your website's contents).  Search does not include
  # providing AI-generated search summaries.
  # ai-input: inputting content into one or more AI models
  # (e.g., retrieval augmented generation, grounding, or other
  # real-time taking of content for generative AI search
  # answers).
  # ai-train: training or fine-tuning AI models.

  # ANY RESTRICTIONS EXPRESSED VIA CONTENT-SIGNALS ARE EXPRESS
  # RESERVATIONS OF RIGHTS UNDER ARTICLE 4 OF THE EUROPEAN
  # UNION DIRECTIVE 2019/790 ON COPYRIGHT AND RELATED RIGHTS
  # IN THE DIGITAL SINGLE MARKET.
  """

  @type policy :: %{blocked: [String.t()], ai_train: nil | String.t()}

  @doc "The robots text served when the editors have written none."
  @spec default_robots() :: String.t()
  def default_robots, do: @default_robots

  @doc """
  The robots text for `seo`: its custom lines, the generated policy block and
  a `Sitemap:` line for `sitemap_url` unless the custom lines name one.
  """
  @spec render(map(), String.t() | nil) :: String.t()
  def render(seo, sitemap_url \\ nil) do
    custom = seo |> Map.get(:robots) |> custom_lines()

    case policy_block(policy(seo)) do
      nil -> custom
      block -> String.trim_trailing(custom) <> "\n\n" <> block
    end
    |> add_sitemap(sitemap_url)
  end

  @doc """
  Names the sitemap at the end of `robots`, unless there is none or the
  editors' text already names one.
  """
  @spec add_sitemap(String.t(), String.t() | nil) :: String.t()
  def add_sitemap(robots, nil), do: robots

  def add_sitemap(robots, url) do
    if robots =~ ~r/^\s*sitemap\s*:/im do
      robots
    else
      String.trim_trailing(robots) <> "\n\nSitemap: #{url}\n"
    end
  end

  @doc """
  The editors' robots text, or the default when there is none, without a
  generated block pasted into it.
  """
  @spec custom_lines(String.t() | nil) :: String.t()
  def custom_lines(robots) when robots in [nil, ""], do: @default_robots

  def custom_lines(robots) when is_binary(robots) do
    if String.contains?(robots, @begin_marker) do
      pattern = ~r/^#{Regex.escape(@begin_marker)}.*?^#{Regex.escape(@end_marker)}[^\n]*\n?/ms

      case String.trim(Regex.replace(pattern, robots, "")) do
        "" -> @default_robots
        text -> text <> "\n"
      end
    else
      robots
    end
  end

  @doc """
  The normalized crawler policy of `seo`, or of a stored `crawler_policy` map.
  Unknown crawlers and values are ignored.
  """
  @spec policy(map() | nil) :: policy()
  def policy(%{crawler_policy: policy}), do: policy(policy)
  def policy(%{__struct__: _}), do: policy(nil)

  def policy(policy) when is_map(policy) do
    crawlers = Map.get(policy, "crawlers") || Map.get(policy, :crawlers)
    crawlers = if is_map(crawlers), do: crawlers, else: %{}

    blocked = Enum.filter(Crawlers.tokens(), &(Map.get(crawlers, &1) == "block"))
    ai_train = Map.get(policy, "ai_train") || Map.get(policy, :ai_train)
    ai_train = if ai_train in ["yes", "no"], do: ai_train

    %{blocked: blocked, ai_train: ai_train}
  end

  def policy(_), do: %{blocked: [], ai_train: nil}

  @doc "Whether `token` is blocked by `policy`."
  @spec blocked?(policy(), String.t()) :: boolean()
  def blocked?(%{blocked: blocked}, token), do: token in blocked

  @doc """
  The `Content-Signal` value for `policy`, or `nil` when the policy is the
  default and nothing is generated.
  """
  @spec content_signal(policy()) :: String.t() | nil
  def content_signal(%{blocked: [], ai_train: nil}), do: nil

  def content_signal(%{blocked: blocked, ai_train: ai_train}) do
    input_crawlers = Enum.map(Crawlers.with_purpose(:search) ++ Crawlers.with_purpose(:user), & &1.token)
    ai_input = if Enum.all?(input_crawlers, &(&1 in blocked)), do: "no", else: "yes"

    ["search=yes", "ai-input=#{ai_input}", ai_train && "ai-train=#{ai_train}"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  @doc """
  The generated block for `policy`, between its marker comments, or `nil`
  for the default policy.

  Blocked crawlers each get a group of their own. The `Content-Signal` line
  sits in a `User-agent: *` group of its own, last and without rules, so it
  never changes what the editors' `User-agent: *` rules allow.
  """
  @spec policy_block(policy()) :: String.t() | nil
  def policy_block(policy) do
    case content_signal(policy) do
      nil ->
        nil

      signal ->
        header = @begin_marker <> " (Configuration → SEO). Changes here are replaced."
        groups = Enum.map(policy.blocked, &"User-agent: #{&1}\nDisallow: /")
        signal_group = String.trim(@content_signals_policy) <> "\n\nUser-agent: *\nContent-Signal: #{signal}"

        Enum.join([header | groups] ++ [signal_group, @end_marker], "\n\n") <> "\n"
    end
  end
end
