defmodule Brando.SEO.Crawlers do
  @moduledoc """
  The AI crawlers Configuration → SEO lets editors allow or block.

  Each crawler has the token it answers to in `robots.txt`, its vendor and its
  purpose:

    * `:search` — builds an index for an AI search product. Blocking it keeps
      the site out of that product's answers and links.
    * `:user` — fetches a page because a user of an AI product asked for it.
      These fetchers say robots.txt may not apply to them, so a block is a
      request rather than a guarantee.
    * `:training` — collects pages that may be used to train models.

  Traditional search crawlers (Googlebot, Bingbot) are not listed: blocking
  them takes the site out of search, which is never what this setting is for.
  Google's AI Overviews come from Googlebot, not `Google-Extended`; they follow
  the per-entry `nosnippet` and `max-snippet` settings of `Brando.Trait.Meta`.

  Sources, checked October 2026:

    * OpenAI — https://developers.openai.com/api/docs/bots
    * Anthropic — https://support.claude.com/en/articles/8896518
    * Perplexity — https://docs.perplexity.ai/guides/bots
    * Google — https://developers.google.com/search/docs/crawling-indexing/google-common-crawlers
    * Apple — https://support.apple.com/en-us/119829
    * Common Crawl — https://commoncrawl.org/ccbot
    * Meta — https://developers.facebook.com/docs/sharing/webmasters/web-crawlers/
    * Amazon — https://developer.amazon.com/amazonbot
    * ByteDance (Bytespider) has no public documentation page; its token is the
      one it sends.
  """
  use Gettext, backend: Brando.Gettext

  @type purpose :: :search | :user | :training
  @type t :: %{token: String.t(), vendor: String.t(), purpose: purpose(), description: String.t()}

  @crawlers [
    {"OAI-SearchBot", "OpenAI", :search},
    {"Claude-SearchBot", "Anthropic", :search},
    {"PerplexityBot", "Perplexity", :search},
    {"ChatGPT-User", "OpenAI", :user},
    {"Claude-User", "Anthropic", :user},
    {"Perplexity-User", "Perplexity", :user},
    {"GPTBot", "OpenAI", :training},
    {"ClaudeBot", "Anthropic", :training},
    {"Google-Extended", "Google", :training},
    {"Applebot-Extended", "Apple", :training},
    {"meta-externalagent", "Meta", :training},
    {"Amazonbot", "Amazon", :training},
    {"CCBot", "Common Crawl", :training},
    {"Bytespider", "ByteDance", :training}
  ]

  @tokens Enum.map(@crawlers, &elem(&1, 0))
  @purposes [:search, :user, :training]

  @doc "Every known crawler, in the order the settings list them."
  @spec all() :: [t()]
  def all do
    Enum.map(@crawlers, fn {token, vendor, purpose} ->
      %{token: token, vendor: vendor, purpose: purpose, description: description(token)}
    end)
  end

  @doc "The robots.txt tokens of every known crawler."
  @spec tokens() :: [String.t()]
  def tokens, do: @tokens

  @doc "The purposes, in the order the settings group them."
  @spec purposes() :: [purpose()]
  def purposes, do: @purposes

  @doc "The crawlers with `purpose`."
  @spec with_purpose(purpose()) :: [t()]
  def with_purpose(purpose), do: Enum.filter(all(), &(&1.purpose == purpose))

  @doc "A heading for the crawlers with `purpose`."
  @spec purpose_label(purpose()) :: String.t()
  def purpose_label(:search), do: gettext("AI search")
  def purpose_label(:user), do: gettext("Fetches for a user")
  def purpose_label(:training), do: gettext("Model training")

  defp description("OAI-SearchBot"), do: gettext("ChatGPT search results")
  defp description("Claude-SearchBot"), do: gettext("Claude search results")
  defp description("PerplexityBot"), do: gettext("Perplexity search results")
  defp description("ChatGPT-User"), do: gettext("Pages a ChatGPT user asks for. May not follow robots.txt")
  defp description("Claude-User"), do: gettext("Pages a Claude user asks for")
  defp description("Perplexity-User"), do: gettext("Pages a Perplexity user asks for. Usually ignores robots.txt")
  defp description("GPTBot"), do: gettext("Training OpenAI's models")
  defp description("ClaudeBot"), do: gettext("Training Anthropic's models")
  defp description("Google-Extended"), do: gettext("Gemini training and grounding; not AI Overviews")
  defp description("Applebot-Extended"), do: gettext("Training Apple Intelligence; uses what Applebot fetched")
  defp description("meta-externalagent"), do: gettext("Training Meta's models")
  defp description("Amazonbot"), do: gettext("Amazon's services, including model training")
  defp description("CCBot"), do: gettext("Common Crawl's open dataset, widely used for training")
  defp description("Bytespider"), do: gettext("Training ByteDance's models")
end
