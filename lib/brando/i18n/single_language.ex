defmodule Brando.I18n.SingleLanguage do
  @moduledoc """
  Whether the site has only one content language.

  Blueprints hide their language pickers with
  `hidden: &Brando.I18n.SingleLanguage.single_language?/1`. A capture in a
  blueprint is a compile-time reference, so this module stays a leaf that
  only reads the application env: pointing at `Brando.I18n` instead closed a
  compile-connected cycle through `Brando`.
  """

  @doc "True when `:languages` has at most one entry. The form is ignored."
  def single_language?(_form \\ nil), do: length(Brando.RuntimeConfig.get(:languages) || []) <= 1
end
