defmodule Brando.Villain.RenderInvalidation do
  @moduledoc false

  # A reference can be followed by field/bracket access, or used as a bare
  # value before a Liquid tag/filter/comparison delimiter. Requiring one of
  # those suffixes avoids treating ordinary prose such as "our globals are…"
  # as a dependency while still covering `{% if links %}` and
  # `{% for link in links %}`.
  @liquid_reference_suffix ~S"([\.\[]|[[:space:]]*[%}|=!<>])"

  @reference_patterns Map.new(
                        ~w(configs globals identity links navigation)a,
                        fn name ->
                          source = Atom.to_string(name)
                          {name, "(@#{source}|#{source}#{@liquid_reference_suffix})"}
                        end
                      )

  @doc false
  def patterns(names) when is_list(names) do
    Enum.map(names, &{&1, Map.fetch!(@reference_patterns, &1)})
  end
end
