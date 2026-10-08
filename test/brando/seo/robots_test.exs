defmodule Brando.SEO.RobotsTest do
  use ExUnit.Case, async: true

  alias Brando.SEO.Crawlers
  alias Brando.SEO.Robots

  @custom "User-agent: *\nDisallow: /admin/\nDisallow: /private/\n"

  defp seo(policy, robots \\ @custom), do: %Brando.Sites.SEO{robots: robots, crawler_policy: policy}

  test "the default policy leaves the robots text as it was" do
    assert Robots.render(seo(nil)) == @custom
    assert Robots.render(seo(%{"crawlers" => %{"GPTBot" => "allow"}})) == @custom
    assert Robots.render(seo(nil, nil)) == Robots.default_robots()
  end

  test "a blocked crawler gets its own group after the custom lines, which are kept" do
    robots = Robots.render(seo(%{"crawlers" => %{"GPTBot" => "block", "CCBot" => "block"}}))

    assert String.starts_with?(robots, @custom)
    assert robots =~ "# BEGIN Brando AI crawler policy"
    assert robots =~ "User-agent: GPTBot\nDisallow: /\n"
    assert robots =~ "User-agent: CCBot\nDisallow: /\n"
    assert robots =~ ~r/# END Brando AI crawler policy\n$/
    refute robots =~ "User-agent: ClaudeBot"
  end

  test "the Content-Signal line sits last, in a rule-less group for every crawler" do
    robots = Robots.render(seo(%{"crawlers" => %{"Bytespider" => "block"}, "ai_train" => "no"}))

    assert robots =~ "User-agent: *\nContent-Signal: search=yes, ai-input=yes, ai-train=no\n\n# END"

    [_custom, block] = String.split(robots, "# BEGIN", parts: 2)
    refute block =~ ~r/^Allow:/m
    assert block =~ "ARTICLE 4 OF THE EUROPEAN"
  end

  test "ai-input follows the AI search and user-fetch crawlers, ai-train its own setting" do
    input_crawlers = Enum.map(Crawlers.with_purpose(:search) ++ Crawlers.with_purpose(:user), & &1.token)

    some = Robots.policy(%{"crawlers" => %{"PerplexityBot" => "block"}})
    assert Robots.content_signal(some) == "search=yes, ai-input=yes"

    all = Robots.policy(%{"crawlers" => Map.new(input_crawlers, &{&1, "block"}), "ai_train" => "yes"})
    assert Robots.content_signal(all) == "search=yes, ai-input=no, ai-train=yes"

    only_training = Robots.policy(%{"ai_train" => "no"})
    assert Robots.content_signal(only_training) == "search=yes, ai-input=yes, ai-train=no"
    assert Robots.policy_block(only_training) =~ "Content-Signal: search=yes, ai-input=yes, ai-train=no"
  end

  test "unknown crawlers and values are ignored" do
    assert Robots.policy(%{"crawlers" => %{"EvilBot" => "block", "GPTBot" => "maybe"}, "ai_train" => "sometimes"}) ==
             %{blocked: [], ai_train: nil}
  end

  test "a generated block pasted into the custom text is not written twice" do
    policy = %{"crawlers" => %{"GPTBot" => "block"}}
    once = Robots.render(seo(policy))
    twice = Robots.render(seo(policy, once))

    assert twice == once
    assert Robots.custom_lines(once) == @custom
  end

  test "the sitemap comes after the generated block, unless the custom text names one" do
    robots = Robots.render(seo(%{"ai_train" => "no"}), "https://example.com/sitemaps/sitemap.xml.gz")
    assert robots =~ ~r/# END Brando AI crawler policy\n\nSitemap: https:\/\/example.com\/sitemaps\/sitemap.xml.gz\n$/

    custom = @custom <> "Sitemap: https://example.com/own.xml\n"
    refute Robots.render(seo(nil, custom), "https://example.com/other.xml") =~ "other.xml"
  end

  test "every known crawler has a vendor, a purpose and a description" do
    assert length(Crawlers.all()) == length(Crawlers.tokens())

    for crawler <- Crawlers.all() do
      assert crawler.purpose in Crawlers.purposes()
      assert crawler.vendor != ""
      assert crawler.description != ""
    end

    for token <-
          ~w(GPTBot OAI-SearchBot ChatGPT-User ClaudeBot Claude-SearchBot Claude-User PerplexityBot Perplexity-User Google-Extended Applebot-Extended CCBot Bytespider meta-externalagent Amazonbot) do
      assert token in Crawlers.tokens()
    end
  end
end
