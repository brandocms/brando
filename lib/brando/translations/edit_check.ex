defmodule Brando.Translations.EditCheck do
  @moduledoc """
  Judges whether an edit to a source text leaves its translations correct,
  so a spelling fix need not send every language back to review.

  Code decides what it can compute exactly, and an evaluation model
  (`Brando.AI.evaluate/3`) answers the rest:

    * the same words after whitespace is collapsed → `:minor`
    * the same words with different markup → `:review`, since the
      translation's formatting must follow
    * different numbers → `:review`; evaluation models do not compare
      numbers reliably
    * otherwise the model classifies the edit, and it is `:minor` only when
      it is a correction with confidence and a translation is unlikely to
      need changing

  Anything uncertain is `:review`, which is what every source edit gets
  without this check.
  """

  alias Brando.AI

  @kinds %{
    "correction" =>
      "Fixes spelling, typos, punctuation, capitalisation or spacing. Every word means exactly what it meant before.",
    "rewording" => "Changes or reorders words, but a reader learns the same facts and gets the same message as before.",
    "meaning" =>
      "Changes a fact, name, claim, instruction or the tone, so a reader learns something different than before.",
    "content" => "Adds or removes a phrase, sentence or piece of information."
  }

  @defaults [min_confidence: 0.8, max_retranslate: 0.2]

  @type result :: %{
          verdict: :minor | :review,
          reason: :unchanged | :markup | :numbers | :model,
          kind: String.t() | nil,
          confidence: float() | nil,
          retranslate: float() | nil,
          model: String.t() | nil
        }

  @doc """
  Checks the edit from `previous` to `current`, both strings that may hold HTML.

  Options: `:language` (a language code, named to the model),
  `:min_confidence` for the model's classification (default 0.8),
  `:max_retranslate` for the probability that a translation needs changing
  (default 0.2), and `:ai_opts` for `Brando.AI.evaluate/3`.
  """
  @spec check(String.t() | nil, String.t() | nil, keyword()) :: {:ok, result()} | {:error, term()}
  def check(previous, current, opts \\ []) do
    case precheck(previous, current) do
      {:ok, _result} = decided -> decided
      :ask -> ask(plain(previous), plain(current), Keyword.merge(@defaults, opts))
    end
  end

  @doc """
  The verdict code can reach on its own, or `:ask` when the edit needs the
  model.
  """
  @spec precheck(String.t() | nil, String.t() | nil) :: {:ok, result()} | :ask
  def precheck(previous, current) do
    before_text = plain(previous)
    after_text = plain(current)

    cond do
      normalize(previous) == normalize(current) -> {:ok, decided(:minor, :unchanged)}
      before_text == after_text -> {:ok, decided(:review, :markup)}
      numbers(before_text) != numbers(after_text) -> {:ok, decided(:review, :numbers)}
      true -> :ask
    end
  end

  @doc "The questions asked about each edit, for inspection and tests."
  def questions do
    %{
      kind: %{
        type: :choice,
        instructions: "What kind of edit turned `before` into `after`?",
        criteria: @kinds
      },
      retranslate: %{
        type: :boolean,
        instructions:
          "Would a correct translation of `before` into another language have to be changed to be a correct translation of `after`?",
        criteria: %{
          true: "The translation would say something different from `after`.",
          false: "The same translation is still correct for `after`."
        }
      }
    }
  end

  defp ask(before_text, after_text, opts) do
    state =
      %{before: before_text, after: after_text}
      |> put_language(opts[:language])

    with {:ok, %{answers: answers, model: model}} <- AI.evaluate(state, questions(), opts[:ai_opts] || []) do
      kind = get_in(answers, ["kind", "choice"])
      confidence = get_in(answers, ["kind", "confidence"])
      retranslate = get_in(answers, ["retranslate", "probability"])

      minor? =
        kind == "correction" and is_number(confidence) and confidence >= opts[:min_confidence] and
          is_number(retranslate) and retranslate <= opts[:max_retranslate]

      {:ok,
       %{
         verdict: if(minor?, do: :minor, else: :review),
         reason: :model,
         kind: kind,
         confidence: confidence,
         retranslate: retranslate,
         model: model
       }}
    end
  end

  defp decided(verdict, reason),
    do: %{verdict: verdict, reason: reason, kind: nil, confidence: nil, retranslate: nil, model: nil}

  defp put_language(state, nil), do: state
  defp put_language(state, language), do: Map.put(state, :language, AI.language_name(language))

  defp plain(value), do: value |> to_string() |> HtmlSanitizeEx.strip_tags() |> normalize()

  defp normalize(value), do: value |> to_string() |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp numbers(text), do: Regex.scan(~r/\d+(?:[.,]\d+)*/u, text)
end
