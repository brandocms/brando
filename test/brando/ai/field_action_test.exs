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
end
