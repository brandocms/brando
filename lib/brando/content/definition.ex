defmodule Brando.Content.Definition do
  @moduledoc """
  Declarative, portable module and table-template definitions.

  Definitions can be authored as Spark modules or loaded from literal `.exs`
  declarations with `Brando.Content.Definitions.read/1`. See the
  [module definitions guide](module_definitions.md) for the export/import workflow.

      defmodule MySite.Hero do
        use Brando.Content.Definition

        uid "my-site-hero"
        name en: "Hero"
        namespace en: "Sections"
        help_text en: "Introductory section"
        class "hero"

        vars do
          var :title, :string do
            label "Title"
            default "Hello"
          end
        end

        template :liquid, "<h1>{{ title }}</h1>"
      end

  The file loader accepts declarations and literal values, not executable
  Elixir expressions. Compiled Spark definitions may also be passed explicitly
  to `Brando.Content.Definitions.from_modules/1`.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [Brando.Content.Definition.Dsl]],
    opts_to_document: []

  alias Brando.Content.Definition.Dsl

  @doc false
  def specification(module) do
    options =
      Dsl.options()
      |> Keyword.keys()
      |> Map.new(&{&1, Spark.Dsl.Extension.get_opt(module, [:definition], &1, :__unset__)})
      |> Map.reject(fn {_key, value} -> value == :__unset__ end)

    %{
      source: Spark.Dsl.Extension.get_persisted(module, :file) || to_string(module.module_info(:compile)[:source]),
      module: Atom.to_string(module),
      options: options,
      refs: entities(module, :refs),
      vars: entities(module, :vars),
      templates: entities(module, :definition),
      children: entities(module, :children)
    }
  end

  defp entities(module, section) do
    module
    |> Spark.Dsl.Extension.get_entities([section])
    |> Enum.map(&Map.from_struct/1)
  end
end
