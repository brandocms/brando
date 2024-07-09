defmodule Brando.Content.AlternateEntries do
  @doc """
  Preload the alternate entries for a translatable schema
  """
  def preloads_for(schema) do
    if schema.has_trait(Brando.Trait.Translatable) and schema.has_alternates?() do
      case schema.__absolute_url_preloads__() do
        [] ->
          [:alternate_entries]

        extracted_preloads ->
          [alternate_entries: extracted_preloads]
      end
    else
      []
    end
  end
end
