defmodule Brando.I18n.SingleLanguage do
  @moduledoc """
  Whether the site has only one content language.

  Blueprints hide their language pickers with
  `hidden: &Brando.I18n.SingleLanguage.single_language?/1`. A capture in a
  blueprint is a compile-time reference, so this module stays a leaf that
  only reads `Brando.Languages`, itself a leaf: pointing at `Brando.I18n`
  instead closed a compile-connected cycle through `Brando`.
  """

  @doc "True when the current site (`Brando.Languages`) has at most one language. The form is ignored."
  def single_language?(_form \\ nil), do: length(Brando.Languages.languages()) <= 1
end
