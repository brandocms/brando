defmodule Brando.Content.StartingTemplates do
  @moduledoc """
  The content templates an empty block field offers to start from.

  A template (Configuration → Templates) is a set of blocks with a name and a
  namespace. A block field offers the templates of one namespace:

    * the field's `template_namespace` option, when it has one

          blocks :blocks, template_namespace: "projects"

    * otherwise the entry schema's own name: a template in namespace `cases`
      (or `case`) is offered to `MyApp.Cases.Case`.

  Namespaces are compared without regard to case.
  """

  import Ecto.Query

  alias Brando.Content.Template
  alias Brando.Repo

  @type summary :: %{
          id: integer(),
          name: String.t(),
          instructions: String.t() | nil,
          block_count: non_neg_integer(),
          modules: [%{name: map() | nil}]
        }

  @doc "The namespaces a field of `schema` takes templates from."
  @spec namespaces(module(), String.t() | nil) :: [String.t()]
  def namespaces(_schema, namespace) when is_binary(namespace) and namespace != "",
    do: [String.downcase(namespace)]

  def namespaces(schema, _none) do
    naming = schema.__naming__()
    [naming.plural, naming.singular] |> Enum.map(&String.downcase(to_string(&1))) |> Enum.uniq()
  rescue
    _ -> []
  end

  @doc """
  The templates a field of `schema` offers, in their own order, each with the
  modules of its root blocks, to say what it holds.
  Templates without blocks are left out: there is nothing to start from.
  """
  @spec list(module(), String.t() | nil) :: [summary()]
  def list(schema, namespace \\ nil) do
    case namespaces(schema, namespace) do
      [] ->
        []

      namespaces ->
        templates =
          Repo.all(
            from t in Template,
              where: fragment("lower(?)", t.namespace) in ^namespaces and is_nil(t.deleted_at),
              order_by: [asc: t.sequence, asc: t.id],
              select: %{id: t.id, name: t.name, instructions: t.instructions}
          )

        blocks = root_modules(Enum.map(templates, & &1.id))

        templates
        |> Enum.map(fn template ->
          modules = Map.get(blocks, template.id, [])
          Map.merge(template, %{block_count: length(modules), modules: modules})
        end)
        |> Enum.reject(&(&1.block_count == 0))
    end
  end

  @doc """
  The template's root blocks, in order, loaded as deep as a copy needs:
  children, refs, vars and table rows.
  """
  @spec blocks(integer()) :: [struct()]
  def blocks(template_id) do
    case Repo.get(Template, template_id) do
      nil ->
        []

      template ->
        template
        |> Repo.preload(Brando.Blueprint.preloads_for(Template))
        |> Map.get(:entry_blocks, [])
        |> Enum.sort_by(&{&1.sequence, &1.id})
        |> Enum.map(& &1.block)
    end
  end

  # %{template_id => [%{name:}]}: the module behind each root block.
  defp root_modules([]), do: %{}

  defp root_modules(template_ids) do
    Template.Blocks
    |> join(:inner, [j], b in Brando.Content.Block, on: b.id == j.block_id)
    |> join(:left, [_j, b], m in Brando.Content.Module, on: m.id == b.module_id)
    |> where([j], j.entry_id in ^template_ids)
    |> order_by([j], asc: j.entry_id, asc: j.sequence, asc: j.id)
    |> select([j, _b, m], {j.entry_id, %{name: m.name}})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
