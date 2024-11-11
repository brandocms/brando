defmodule Brando.Migrations.MoveDatasourceToModule do
  use Ecto.Migration
  import Ecto.Query

  def change do
    alter table(:content_modules) do
      add :datasource, :boolean, default: false
      add :datasource_module, :string
      add :datasource_type, :string
      add :datasource_query, :string
    end

    flush()

    villain_schemas =
      Enum.reject(
        Brando.Villain.list_blocks(),
        &(elem(&1, 0) in [
            Brando.Content.Template,
            Brando.Pages.Page,
            Brando.Pages.Fragment
            # your schemas here
          ])
      )

    # since these are old now, we use :data as field name (since list_blocks will return :blocks for these)
    villain_schemas =
      villain_schemas ++
        [
          {Brando.Content.Template, [%{name: :data}]},
          {Brando.Pages.Page, [%{name: :data}]},
          {Brando.Pages.Fragment, [%{name: :data}]}
        ]

    for {schema, attrs} <- villain_schemas,
        %{name: data_field} <- attrs do
      query =
        from(m in schema.__schema__(:source),
          select: %{id: m.id, data: field(m, ^data_field)},
          where: not is_nil(field(m, ^data_field)),
          order_by: [desc: m.id]
        )

      entries = Brando.Repo.all(query)

      for entry <- entries do
        new_data = replace_datasources(entry.data)
        update_args = Keyword.new([{data_field, new_data}])

        query =
          from(m in schema.__schema__(:source),
            where: m.id == ^entry.id,
            update: [set: ^update_args]
          )

        Brando.Repo.update_all(query, [])
      end
    end
  end

  def down do
  end

  def replace_datasources(list, root \\ :root)

  def replace_datasources(list, root) when is_list(list) do
    list
    |> Enum.reduce([], fn item, acc -> [replace_datasources(item, root) | acc] end)
    |> Enum.reverse()
  end

  def replace_datasources(
        %{
          "type" => "container"
        } = block,
        _
      ) do
    # search through blocks
    put_in(
      block,
      [Access.key("data"), Access.key("blocks")],
      replace_datasources(block["data"]["blocks"], :container)
    )
  end

  def replace_datasources(
        %{
          "type" => "module"
        } = module_block,
        _
      ) do
    {mod, refs} =
      Enum.reduce(module_block["data"]["refs"] || [], {module_block, []}, fn
        %{"data" => %{"type" => "datasource", "data" => ds_data}, "name" => ref_name},
        {updated_mod, updated_refs} ->
          ds_module_query =
            from(m in "content_modules",
              select: [:id, :vars, :refs, :wrapper, :code],
              where: m.id == ^ds_data["module_id"]
            )

          ds_module = Brando.Repo.one(ds_module_query)

          mod_module_query =
            from(m in "content_modules",
              select: [:id, :vars, :refs, :wrapper, :code],
              where: m.id == ^module_block["data"]["module_id"]
            )

          mod_module = Brando.Repo.one(mod_module_query)

          updated_vars =
            mod_module.vars
            |> update_vars_with_arg(ds_data["arg"])
            |> update_vars_with_limit(ds_data["limit"])

          wrapped_code = """
          {% datasource %}
            #{ds_module.code}
          {% enddatasource %}
          """

          new_code = String.replace(mod_module.code, "{% ref refs.#{ref_name} %}", wrapped_code)

          module_update_query =
            from(m in "content_modules",
              select: [m.id],
              where: m.id == ^mod_module.id,
              update: [
                set: [
                  code: ^new_code,
                  datasource: true,
                  datasource_module: ^ds_data["module"],
                  datasource_type: ^ds_data["type"],
                  datasource_query: ^ds_data["query"],
                  vars: ^updated_vars
                ]
              ]
            )

          Brando.Repo.update_all(module_update_query, [])

          updated_mod =
            updated_mod
            |> put_in(["data", "datasource"], true)
            |> put_in(["data", "datasource_selected_ids"], ds_data["ids"])

          {updated_mod, updated_refs}

        ref, {updated_mod, updated_refs} ->
          {updated_mod, updated_refs ++ List.wrap(ref)}
      end)

    put_in(mod, [Access.key("data"), Access.key("refs")], refs)
  end

  # ROOT datasource
  def replace_datasources(
        %{
          "type" => "datasource",
          "data" => %{
            "module_id" => module_id,
            "module" => datasource_module,
            "type" => datasource_type,
            "query" => datasource_query,
            "limit" => datasource_limit,
            "arg" => datasource_arg,
            "ids" => ids
          }
        },
        scope
      )
      when scope in [:root, :container] do
    module_query =
      from(m in "content_modules",
        select: [:id, :vars, :refs, :wrapper],
        where: m.id == ^module_id
      )

    module = Brando.Repo.one(module_query)

    updated_vars =
      (module.vars || [])
      |> update_vars_with_arg(datasource_arg)
      |> update_vars_with_limit(datasource_limit)

    module_update_query =
      from(m in "content_modules",
        select: [m.id],
        where: m.id == ^module_id,
        update: [
          set: [
            datasource: true,
            datasource_module: ^datasource_module,
            datasource_type: ^datasource_type,
            datasource_query: ^datasource_query,
            vars: ^updated_vars
          ]
        ]
      )

    Brando.Repo.update_all(module_update_query, [])

    module = Brando.Repo.one(module_query)

    # build a module block from the updated module -^
    generated_uid = Brando.Utils.generate_uid()
    refs_with_generated_uids = Brando.Villain.add_uid_to_refs(module.refs)

    vars_for_block = set_block_var(updated_vars, datasource_arg)

    # if module.wrapper is true, this is a multi block!
    %{
      type: "module",
      data: %{
        module_id: module_id,
        multi: module.wrapper,
        datasource: true,
        datasource_selected_ids: ids,
        vars: vars_for_block,
        refs: refs_with_generated_uids
      },
      uid: generated_uid
    }
  end

  # fall through -- usually for legacy blocks not in module or container
  def replace_datasources(value, _target) do
    value
  end

  defp set_block_var(vars, arg) do
    case Enum.find(vars, &(&1["key"] == "arg")) do
      nil ->
        vars

      _ ->
        put_in(vars, [Access.filter(&(&1["key"] == "arg")), "value"], arg)
    end
  end

  defp update_vars_with_arg(nil, nil), do: []
  defp update_vars_with_arg(vars, nil), do: vars

  defp update_vars_with_arg(vars, arg) do
    case Enum.find(vars, &(&1["key"] == "arg")) do
      nil ->
        arg_var = %{
          "important" => true,
          "instructions" => nil,
          "placeholder" => nil,
          "key" => "arg",
          "value" => arg,
          "type" => "string",
          "label" => "Arg"
        }

        [arg_var | vars]

      _ ->
        vars
    end
  end

  defp update_vars_with_limit(nil, nil), do: []
  defp update_vars_with_limit(vars, nil), do: vars

  defp update_vars_with_limit(vars, limit) do
    limit_var = %{
      "important" => true,
      "instructions" => nil,
      "placeholder" => nil,
      "key" => "limit",
      "value" => limit,
      "type" => "string",
      "label" => "Limit"
    }

    [limit_var | vars]
  end
end
