defmodule Brando.Villain.RichTextTemplateReadsTest do
  @moduledoc """
  What a template author sees of rich text: a top-level field any form draws
  as rich text prints as markup, `size` of a row gives 0, `markdown` on rich
  text gives its markup, and one render sanitizes a field's value once.
  """
  # Sanitizer runs are counted with a trace session of its own, on this
  # process only
  use Brando.ConnCase, async: true

  alias Brando.RichTextRows.Entry
  alias Brando.RichTextRows.Quote
  alias Brando.SyncTest.Article
  alias Brando.Villain
  alias Brando.Villain.Filters
  alias Brando.Villain.TemplateView
  alias Ecto.Changeset

  # What an editor typed, stored as rich text stores it: text, not markup
  @typed "<p>&lt;img src=x onerror=alert(1)&gt;</p>"
  @safe ~s(<p>A <strong>quote</strong> with <a href="https://example.com/">a link</a></p>)

  defp render_entry(template, entry), do: Villain.parse_and_render(template, Villain.get_base_context(entry))

  defp active_elements(html), do: html |> Floki.parse_fragment!() |> Floki.find("img, script, [onerror]")

  describe "a top-level field only a named form draws as rich text" do
    # `subtitle` is a `:textarea` in Article's default form and `:rich_text`
    # in its `:notes` form
    test "prints as sanitized markup" do
      html = render_entry("{{ entry.subtitle }}", %Article{title: "T", subtitle: @safe})
      assert html == @safe

      html = render_entry("{{ entry.subtitle }}", %Article{title: "T", subtitle: @typed})
      assert html == @typed
      assert active_elements(html) == []
    end

    test "prints as markup through raw and a filter" do
      html =
        render_entry("{{ entry.subtitle | raw }}|{{ entry.subtitle | truncate: 500 | raw }}", %Article{
          title: "T",
          subtitle: @typed
        })

      assert html == @typed <> "|" <> @typed
    end

    # The rows' rule, and its consequence: plain text typed in the form that
    # draws the field as plain text prints as sanitized markup
    test "plain text typed in the other form prints as sanitized markup" do
      html = render_entry("{{ entry.subtitle }}", %Article{title: "T", subtitle: "John <john@example.com>"})
      refute html =~ "john@example.com"
    end

    test "a save still checks by the default form" do
      assert :subtitle not in Article.__rich_text_fields__()

      params = %{
        title: "A",
        slug: "a",
        language: "en",
        status: "published",
        creator_id: 1,
        subtitle: "<p>A</p><!-- n -->"
      }

      changeset = Article.changeset(%Article{}, params, :system)
      assert Changeset.get_change(changeset, :subtitle) == "<p>A</p><!-- n -->"
    end
  end

  describe "size" do
    test "of a row is 0" do
      entry = %Entry{title: "T", quotes: [%Quote{text: @safe}]}
      assert render_entry("{{ entry.quotes | first | size }}", entry) == "0"
      assert render_entry("{{ entry | size }}", entry) == "0"
    end

    test "of a plain map is its number of pairs, as in Liquid" do
      assert Filters.size(%{"a" => 1, "b" => 2}, %{}) == 2
    end

    test "of text and lists is as before" do
      entry = %Entry{title: "Ti{tle", quotes: [%Quote{text: @safe}, %Quote{text: @safe}]}
      assert render_entry("{{ entry.title | size }} {{ entry.quotes | size }}", entry) == "6 2"
      assert Filters.size(~D[2026-11-21], %{}) == 10
      assert Filters.size(nil, %{}) == 0
    end
  end

  describe "markdown" do
    test "on rich text gives its markup, sanitized" do
      html = render_entry("{{ entry.intro | markdown }}", %Entry{title: "T", intro: @safe})
      refute html =~ "raw HTML omitted"
      assert html == @safe
    end

    test "on rich text keeps what an editor typed as text" do
      html = render_entry("{{ entry.intro | markdown }}", %Entry{title: "T", intro: @typed})
      refute html =~ "raw HTML omitted"
      assert html == @typed
      assert active_elements(html) == []
    end

    test "on rich text after a filter that breaks its markup gives sanitized markup" do
      entry = %Entry{title: "T", intro: ~s(<p>A <a href="https://example.com/">link</a> here</p>)}
      html = render_entry(~s({{ entry.intro | slice: 0, 20 | markdown }}), entry)
      refute html =~ "raw HTML omitted"
      assert html == "<p>A </p>"
    end

    test "on a subform row's rich text gives its markup" do
      entry = %Entry{title: "T", quotes: [%Quote{text: @safe}]}
      html = render_entry("{% for q in entry.quotes %}{{ q.text | markdown }}{% endfor %}", entry)
      assert html == @safe
    end

    test "on plain text is as before" do
      title = "A **b** <em>c</em> & d"
      html = render_entry("{{ entry.title | markdown }}", %Entry{title: title, intro: @safe})
      expected = title |> Brando.HTML.render_markdown() |> Phoenix.HTML.safe_to_string()
      assert html == expected
      assert html =~ "raw HTML omitted"
    end
  end

  describe "sanitizing rich text" do
    # A process traces no calls to itself: a counter is the tracer
    defp count_sanitizer_runs(fun) do
      counter = spawn_link(fn -> count_calls(0) end)
      session = :trace.session_create(__MODULE__, counter, [])

      try do
        :trace.function(session, {Brando.RichText, :render_html, 1}, true, [:global])
        :trace.process(session, self(), true, [:call])
        result = fun.()
        :trace.process(session, self(), false, [:call])
        ref = :trace.delivered(session, self())

        receive do
          {:trace_delivered, _pid, ^ref} -> :ok
        end

        send(counter, {:count, self()})

        receive do
          {:count, count} -> {result, count}
        end
      after
        :trace.session_destroy(session)
      end
    end

    defp count_calls(count) do
      receive do
        {:trace, _pid, :call, {Brando.RichText, :render_html, _args}} -> count_calls(count + 1)
        {:count, pid} -> send(pid, {:count, count})
      end
    end

    test "happens once per field value in a render" do
      intro = "<p>" <> String.duplicate("A <em>long</em> intro &amp; more. ", 50) <> "</p>"
      entry = %Entry{title: "T", intro: intro, quotes: [%Quote{text: intro}, %Quote{text: @safe}]}

      template =
        "{% for i in (1..20) %}{{ entry.intro }}{% for q in entry.quotes %}{{ q.text }}{% endfor %}{% endfor %}"

      {html, runs} = count_sanitizer_runs(fn -> render_entry(template, entry) end)
      assert html =~ "<em>long</em>"
      assert runs == 2
    end

    test "starts again in the next render" do
      entry = %Entry{title: "T", intro: @safe}
      {_html, runs} = count_sanitizer_runs(fn -> render_entry("{{ entry.intro }}{{ entry.intro }}", entry) end)
      assert runs == 1
      {_html, runs} = count_sanitizer_runs(fn -> render_entry("{{ entry.intro }}{{ entry.intro }}", entry) end)
      assert runs == 1
    end

    test "a value markdown is given as it was read is not sanitized again" do
      entry = %Entry{title: "T", intro: @safe}
      {html, runs} = count_sanitizer_runs(fn -> render_entry("{{ entry.intro | markdown }}", entry) end)
      assert html == @safe
      assert runs == 1
    end

    test "outside a render, nothing is kept" do
      before = Process.get_keys()
      view = TemplateView.wrap(%Entry{title: "T", intro: @safe})
      context = Liquex.Context.new(%{})

      {_, runs} =
        count_sanitizer_runs(fn ->
          for _ <- 1..3, do: TemplateView.fetch(view, "intro", context)
        end)

      assert runs == 3
      # The marks outside a render are bounded on their own
      assert (Process.get_keys() -- before) -- [{TemplateView, :rich_texts}] == []
    end
  end
end
