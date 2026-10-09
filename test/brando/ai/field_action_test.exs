defmodule Brando.AI.FieldActionTest do
  use ExUnit.Case, async: true

  alias Brando.AI.FieldAction
  alias Brando.Blueprint.Forms.AIAction

  @action %AIAction{name: :summarize, prompt: "Summarize the article.", from: [:title, :body]}

  describe "prompt/3" do
    test "the instruction, the constraints and the fields it reads, in the entry's language" do
      action = %{@action | max: 160, tone: "plain and factual"}

      prompt =
        FieldAction.prompt(action, [title: "Fjordhuset", body: "Et hus ved fjorden."], language: "no", type: :textarea)

      assert prompt ==
               """
               Summarize the article.
               Write in Norsk.
               Tone: plain and factual.
               Use at most 160 characters.
               Return only the text for the field: no quotes, Markdown or commentary.

               Context:
               title: Fjordhuset
               body: Et hus ved fjorden.\
               """
    end

    test "an action's own language wins over the entry's" do
      prompt = FieldAction.prompt(%{@action | language: "en"}, [title: "Fjordhuset"], language: "no")

      assert prompt =~ "Write in English."
      refute prompt =~ "Norsk"
    end

    test "without a language, the reply follows the context" do
      assert FieldAction.prompt(@action, title: "Fjordhuset") =~ "Write in the language of the context."
    end

    test "leaves out the constraints the action does not declare" do
      prompt = FieldAction.prompt(@action, [title: "Fjordhuset"], language: "en")

      refute prompt =~ "Tone:"
      refute prompt =~ "characters"
    end

    test "asks for paragraphs for a rich text field" do
      assert FieldAction.prompt(@action, [title: "Fjordhuset"], type: :rich_text) =~
               "paragraphs separated by a blank line"
    end
  end

  describe "clean/1" do
    test "drops the quotes a short reply comes wrapped in" do
      assert FieldAction.clean(~s(  "A house by the fjord"\n)) == "A house by the fjord"
      assert FieldAction.clean("«Et hus ved fjorden»") == "Et hus ved fjorden"
    end

    test "gives a single-line text field one line" do
      assert FieldAction.clean("  A house\n\nby the   fjord \n", :text) == "A house by the fjord"
      assert FieldAction.clean("A house\n\nby the fjord", :textarea) == "A house\n\nby the fjord"
      assert FieldAction.field_value("A house\nby the fjord", :text) == "A house by the fjord"
    end

    test "keeps quotes that belong to the text" do
      assert FieldAction.clean(~s("Home", she said, "is here")) == ~s("Home", she said, "is here")
      assert FieldAction.clean("A house by the fjord") == "A house by the fjord"
    end
  end

  describe "formatting_lost?/1" do
    test "paragraphs and line breaks are kept by plain text" do
      refute FieldAction.formatting_lost?("<p>One</p><p>Two<br>lines</p>")
      refute FieldAction.formatting_lost?(nil)
    end

    test "formatting, links and footnote markers are not" do
      assert FieldAction.formatting_lost?("<p>One <strong>bold</strong></p>")
      assert FieldAction.formatting_lost?(~s(<p><a href="/x">link</a></p>))
      assert FieldAction.formatting_lost?(~s(<p>Text<sup data-footnote="1">1</sup></p>))
      assert FieldAction.formatting_lost?("<h2>Heading</h2>")
    end
  end

  describe "field_value/2" do
    test "rich text gets an escaped paragraph per block of text" do
      assert FieldAction.field_value("First <one>.\n\nSecond\nline.", :rich_text) ==
               "<p>First &lt;one&gt;.</p><p>Second<br>line.</p>"
    end

    test "other fields take the text as it is" do
      assert FieldAction.field_value("First.\n\nSecond.", :textarea) == "First.\n\nSecond."
    end
  end

  describe "for_field/3" do
    test "a meta field's site prompt is a Generate action" do
      assert {[generate], :text, []} = FieldAction.for_field(Brando.Pages.Page, nil, :meta_title)

      assert %AIAction{name: :generate, origin: :site, from: [:title, :blocks, :language]} = generate
      assert generate.prompt =~ "Write an SEO title tag"
    end

    test "after the actions the input for it declares, which keep its options" do
      schema = Brando.MetaDrawerTest.ActionsArticle

      assert {[%{name: :shorten, origin: :ai_actions}, %{name: :generate, origin: :site}], :textarea, opts} =
               FieldAction.for_field(schema, schema.__form__(), :meta_description)

      assert opts[:hidden] == true
    end

    test "an input's own :generate replaces the site prompt's" do
      own = %AIAction{name: :generate, prompt: "Mine.", from: [:title]}
      assert FieldAction.with_site_action([own], Brando.Pages.Page, :meta_title) == [own]
    end

    test "other fields have no site actions" do
      assert {[], nil, []} = FieldAction.for_field(Brando.Pages.Page, nil, :title)
      assert FieldAction.with_site_action([], Brando.Pages.Page, :title) == []
    end
  end

  describe "the Generate of ai: and site prompts" do
    test "carries their model and request options to the model" do
      action = AIAction.generate([prompt: "P", model: "openai:gpt-4o", temperature: 0.1, api_key: "k"], :ai)
      assert FieldAction.ai_opts(action) == [model: "openai:gpt-4o", temperature: 0.1, api_key: "k"]
      assert FieldAction.ai_opts(@action) == []
    end

    test "reads context: as the fields it reads, and needs a prompt" do
      assert %AIAction{from: [:title, :blocks]} =
               AIAction.generate(%{"prompt" => "P", "context" => ["title", :blocks]}, :site)

      assert %AIAction{from: []} = AIAction.generate([prompt: "P"], :site)
      assert AIAction.generate([context: [:title]], :site) == nil
      assert AIAction.generate([prompt: " "], :site) == nil
      assert AIAction.generate(nil, :site) == nil
    end

    test "with no fields to read, the prompt goes alone" do
      action = AIAction.generate([prompt: "Write a tagline."], :ai)
      assert FieldAction.prompt(action, [], type: :text) =~ ~r/\AWrite a tagline\.\n/
      refute FieldAction.prompt(action, [], type: :text) =~ "Context:"
    end
  end
end
