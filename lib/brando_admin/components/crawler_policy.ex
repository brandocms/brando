defmodule BrandoAdmin.Components.CrawlerPolicy do
  @moduledoc """
  The "Crawlers and AI" section of Configuration → SEO: each known AI crawler
  (`Brando.SEO.Crawlers`) with Allow / Block, and the training preference for
  the Content Signals line. The choices are inputs of the SEO form, saved
  with it into `crawler_policy`; `Brando.SEO.Robots` writes them into
  `robots.txt`.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias Brando.SEO.Crawlers
  alias Brando.SEO.Robots

  def render(assigns) do
    field = assigns.form[:crawler_policy]
    policy = Robots.policy(field.value)

    assigns =
      assigns
      |> assign(:name, field.name)
      |> assign(:policy, policy)
      |> assign(:block, Robots.policy_block(policy))
      |> assign(:custom_robots, assigns.form[:robots].value || "")
      |> assign(:robots_url, Brando.Utils.hostname("robots.txt"))

    ~H"""
    <div class="seo-crawlers" id="seo-crawlers">
      <div class="seo-crawlers-intro">
        <p>
          {gettext(
            "Written to robots.txt with Content Signals. Search crawlers like Googlebot and Bingbot are always allowed."
          )}
        </p>
        <a class="seo-crawlers-view" href={@robots_url} target="_blank" rel="noopener">
          {gettext("View robots.txt")}
        </a>
      </div>

      <div class="seo-crawler-table-scroll" tabindex="0" role="region" aria-label={gettext("AI crawlers")}>
        <table class="seo-crawler-table">
          <thead>
            <tr>
              <th scope="col">{gettext("Crawler")}</th>
              <th scope="col">{gettext("Purpose")}</th>
              <th scope="col">{gettext("Access")}</th>
            </tr>
          </thead>
          <tbody :for={purpose <- Crawlers.purposes()} data-purpose={purpose}>
            <tr class="seo-crawler-group">
              <th colspan="3" scope="rowgroup">{Crawlers.purpose_label(purpose)}</th>
            </tr>
            <tr :for={crawler <- Crawlers.with_purpose(purpose)} data-crawler={crawler.token}>
              <td class="seo-crawler-name">
                <strong>{crawler.token}</strong>
                <span>· {crawler.vendor}</span>
              </td>
              <td class="seo-crawler-purpose">
                {crawler.description}
                <small :if={named_in_custom?(@custom_robots, crawler.token)}>
                  {gettext("Also named in the robots text above, which applies as well.")}
                </small>
              </td>
              <td class="seo-crawler-access">
                <.segmented
                  name={"#{@name}[crawlers][#{crawler.token}]"}
                  label={gettext("Access for %{crawler}", crawler: crawler.token)}
                  value={if Robots.blocked?(@policy, crawler.token), do: "block", else: "allow"}
                  options={[{"allow", pgettext("crawler access", "Allow")}, {"block", pgettext("crawler access", "Block")}]}
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="seo-crawler-signal">
        <div>
          <h4>{gettext("Use for model training")}</h4>
          <p>
            {gettext(
              "The ai-train content signal, for every crawler, including ones not listed. Blocking a training crawler above stops it fetching pages; this states how any collected content may be used."
            )}
          </p>
        </div>
        <.segmented
          name={"#{@name}[ai_train]"}
          label={gettext("Use for model training")}
          value={@policy.ai_train || ""}
          options={[{"", gettext("No preference")}, {"yes", gettext("Allow")}, {"no", gettext("Don't allow")}]}
        />
      </div>

      <details class="seo-crawler-lines">
        <summary>{gettext("Lines written to robots.txt")}</summary>
        <pre :if={@block}>{@block}</pre>
        <p :if={!@block}>
          {gettext("None. Nothing is written until a crawler is blocked or a training preference is chosen.")}
        </p>
      </details>

      <p class="seo-crawlers-note">
        {gettext(
          "Google's AI Overviews come from Googlebot, not Google-Extended. They follow each entry's No snippet and Snippet length settings in its meta properties."
        )}
      </p>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  # Radios drawn as one small segmented control. Each option keeps its own
  # input, so the browser's arrow keys move between them.
  defp segmented(assigns) do
    ~H"""
    <div class="seo-segmented" role="radiogroup" aria-label={@label}>
      <label :for={{value, text} <- @options} data-value={value}>
        <input type="radio" name={@name} value={value} checked={@value == value} />
        <span>{text}</span>
      </label>
    </div>
    """
  end

  defp named_in_custom?(robots, token) do
    robots
    |> Robots.custom_lines()
    |> String.match?(~r/^\s*user-agent\s*:\s*#{Regex.escape(token)}\s*$/im)
  end
end
