defmodule E2eProject.FieldActionModel do
  @moduledoc """
  A stand-in model for the AI on fields (`ai_actions:`, the Meta drawer's
  Generate, Write with AI in rich text and Suggest alt text), for
  end-to-end tests. It speaks ReqLLM's `generate_text/3` contract and answers
  in the language the prompt asks for, so a spec can see that the form asked
  for the entry's.

  It is not configured by default, so the rest of the suite runs without AI.
  `POST /e2e/field-ai/on` switches `Brando.AI` to it and `/e2e/field-ai/off`
  switches it back (`E2EFixtureController.field_ai/2`).
  """
  alias ReqLLM.{Context, Message, Response}
  alias ReqLLM.Message.ContentPart

  def generate_text(model, prompt, _opts) when is_binary(prompt), do: {:ok, response(model, prompt, reply(prompt))}

  # Alt text: the image comes in a message with the prompt, which asks for
  # one JSON object of a text per language.
  def generate_text(model, _messages, _opts) do
    {:ok,
     response(
       model,
       "alt text",
       ~s({"en": "Two ferries crossing the fjord at dusk", "no": "To ferjer krysser fjorden i skumringen"})
     )}
  end

  defp response(model, prompt, text) do
    %Response{
      id: "e2e-" <> Integer.to_string(System.unique_integer([:positive])),
      model: model,
      context: Context.new([Context.user(prompt)]),
      message: %Message{role: :assistant, content: [ContentPart.text(text)]},
      usage: %{input_tokens: 120, output_tokens: 30},
      finish_reason: :stop
    }
  end

  # A reply in the language the prompt asks for: a title for the title's
  # actions, otherwise a sentence.
  defp reply(prompt) do
    norwegian? = prompt =~ ~r/^Write in Norsk\.$/m

    case {prompt =~ ~r/Suggest a short title|Shorten the title/, norwegian?} do
      {true, true} -> "Huset ved fjorden"
      {true, false} -> "The house by the fjord"
      {false, true} -> "Et lyst hus ved fjorden, tegnet for lange somre og stille vintre."
      {false, false} -> "A bright house by the fjord, drawn for long summers and quiet winters."
    end
  end
end
