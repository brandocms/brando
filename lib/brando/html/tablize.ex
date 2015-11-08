defmodule Brando.HTML.Tablize do
  @moduledoc """
  Displays model data as a table.
  """

  import Brando.Gettext
  import Brando.HTML, only: [check_or_x: 1, zero_pad: 1]
  import Brando.HTML.Inspect, only: [inspect_field: 3]

  @narrow_fields [:language, :id, :status]
  @narrow_types [:integer, :boolean]
  @date_fields [:inserted_at, :updated_at, :published_at, :deleted_at]

  @doc """
  Converts `records` into a formatted table with dropdown menus.

  ## Example

      tablize(@conn, @users, [
        {gettext("Show"),
         "fa-search", :admin_user_path, :show, :id},
        {gettext("Edit"),
         "fa-edit", :admin_user_path, :edit, :id},
        {gettext("Delete"),
         "fa-trash", :admin_user_path, :delete_confirm, :id},
        {gettext("Show profiles")),
         "fa-search", :admin_user_path, :show_profiles, [:group_id, :id]}
      ], check_or_x: [:avatar], hide: [:password, :last_login, :inserted_at])

  ## Arguments

    * `conn` - a Plug.Conn struct
    * `records` - List of records to render
    * `dropdowns` - List of dropdowns in format:
                    {display_name, icon, helper_path, action,
                     identifier or nil, role or nil}
                    `identifier` is either a field on the record,
                    or a list of fields.

  ## Options

    * `check_or_x` - Provide a list of fields that should be presented
                     with an X or a checkmark.
    * `hide` - List of fields that should not be rendered.
    * `filter` - Boolean. Implements a filtering input box above table.
    * `colgroup` - Column widths if you need to override.
                   Supply as list `[100, nil, nil, 200, nil, 200]`

  """
  def tablize(_, [], _, _), do: "<p>#{gettext("No results")}</p>" |> Phoenix.HTML.raw
  def tablize(_, nil, _, _), do: "<p>#{gettext("No results")}</p>" |> Phoenix.HTML.raw
  def tablize(conn, records, dropdowns, opts) do
    module = List.first(records).__struct__
    colgroup = if opts[:colgroup] do
      render_colgroup(:manual, opts[:colgroup])
    else
      render_colgroup(:auto, module, opts)
    end
    filter_attr =
      if opts[:filter], do:
        ~s( data-filter-table="true"),
      else: ""

    table_header = render_thead(module.__keys__, module, opts)
    table_body = render_tbody(module.__keys__, records, module, conn, dropdowns, opts)
    table = ~s(<table class="table"#{filter_attr}>#{colgroup}#{table_header}#{table_body}</table>)
    filter =
      if opts[:filter] do
        ~s(<div class="filter-input-wrapper pull-right">
             <i class="fa fa-fw fa-search m-r-sm m-l-xs"></i>
             <input type="text" placeholder="Filter" id="filter-input" />
           </div>)
      else
        ""
      end
    Phoenix.HTML.raw([filter|table])
  end

  defp render_colgroup(:auto, module, opts) do
    fields =
      opts[:hide] && module.__keys__ -- opts[:hide] || module.__keys__
    narrow_fields =
      opts[:check_or_x] && @narrow_fields ++ opts[:check_or_x] || @narrow_fields
    colgroups = for f <- fields do
      type = module.__schema__(:type, f)
      cond do
        type in @narrow_types  -> "<col style=\"width: 10px;\">"
        f in narrow_fields     -> "<col style=\"width: 10px;\">"
        f in @date_fields      -> "<col style=\"width: 140px;\">"
        f == :creator          -> "<col style=\"width: 180px;\">"
        true                   -> "<col>"
      end
    end
    # add expander
    colgroups = ["<col style=\"width: 10px;\">"|colgroups]
    # add menu col
    colgroups = colgroups ++ "<col style=\"width: 80px;\">"
    "<colgroup>" <> IO.iodata_to_binary(colgroups) <> "</colgroup>"
  end

  defp render_colgroup(:manual, list) do
    colgroups = for col <- list do
      col && "<col style=\"width: #{col}px;\">" || "<col>"
    end
    colgroups = colgroups ++ "<col style=\"width: 80px;\">"
    "<colgroup>" <> IO.iodata_to_binary(colgroups) <> "</colgroup>"
  end

  defp render_tbody(fields, records, module, conn, dropdowns, opts) do
    if split_by = opts[:split_by] do
      tbodies = for {_, split_recs} <- records |> Brando.Utils.split_by(split_by) do
        do_render_tbody(fields, split_recs, module, conn, dropdowns, opts)
      end
      tbodies |> Enum.join("<tr class=\"splitter\"><td></td></tr>")
    else
      do_render_tbody(fields, records, module, conn, dropdowns, opts)
    end
  end

  defp do_render_tbody(fields, records, module, conn, dropdowns, opts) do
    rendered_trs =
      records
      |> Enum.map(&(do_tr(fields, &1, module, conn, dropdowns, opts)))
      |> Enum.join
    "<tbody>#{rendered_trs}</tbody>"
  end

  defp do_tr(fields, record, module, conn, dropdowns, opts) do
    tr_content = fields
      |> Enum.map(&(do_td(&1, record, module.__schema__(:type, &1), opts)))
      |> Enum.join
    children = case Map.get(record, opts[:children]) do
      nil -> nil
      [] -> nil
      children ->
        child_rows = for child <- children do
          tr_content =
            fields
            |> Enum.map(&(do_td(&1, child, module.__schema__(:type, &1), opts)))
            |> Enum.join
          ~s(<tr data-parent-id="#{record.id}" class="child hidden"><td></td>#{tr_content}#{render_dropdowns(conn, dropdowns, child)}</tr>)
        end
        Enum.join(child_rows)
    end
    expander =
      if children do
        "<td><a href=\"\" class=\"expand-page-children\" data-id=\"#{record.id}\"><i class=\"fa fa-plus\"></i></td>"
      else
        "<td></td>"
      end
    row = "<tr>#{expander}#{tr_content}#{render_dropdowns(conn, dropdowns, record)}</tr>"
    if children do
      row <> children
    else
      row
    end
  end

  defp do_td(:id, record, _type, _opts) do
    ~s(<td data-field="id" class="text-small text-center text-mono text-muted">##{zero_pad(Map.get(record, :id))}</td>)
  end

  defp do_td(field, record, type, opts) do
    unless field in Keyword.get(opts, :hide, []) do
      if field in Keyword.get(opts, :check_or_x, []) do
        ~s(<td data-field="#{field}" class="text-center">#{check_or_x(Map.get(record, field))}</td>)
      else
        ~s(<td data-field="#{field}">#{inspect_field(field, type, Map.get(record, field))}</td>)
      end
    end
  end

  defp render_thead(fields, module, opts) do
    rendered_ths = fields
      |> Enum.map(&(do_th(&1, module, opts[:hide])))
      |> Enum.join
    ~s(<thead><tr><th></th>#{rendered_ths}<th class="text-center">☰</th></tr></thead>)
  end

  defp do_th(:id, _module, _hidden_fields) do
    ~s(<th class="text-center">&#8470;</th>)
  end

  defp do_th(field, module, nil) do
    ~s(<th>#{module.__field__(field)}</th>)
  end

  defp do_th(field, module, hidden_fields) do
    unless field in hidden_fields do
      ~s(<th>#{module.__field__(field)}</th>)
    end
  end

  defp render_dropdowns(conn, dropdowns, record) do
    dropdowns = for dropdown <- dropdowns do
      case tuple_size(dropdown) do
        5 -> {desc, icon, helper, action, param} = dropdown
        6 -> {desc, icon, helper, action, param, role} = dropdown
      end
      fun_params = case param do
        nil -> [Brando.endpoint, action]
        param when is_list(param) ->
          params = Enum.map(param, fn(p) -> Map.get(record, p) end)
          [Brando.endpoint, action, params] |> List.flatten
        param ->
          [Brando.endpoint, action, Map.get(record, param)]
      end

      url = apply(Brando.helpers, helper, fun_params)
      if Brando.HTML.can_render?(conn, %{role: role}) do
        "<li>" <>
        "  <a href=\"" <> url <> "\">" <>
        "    <i class=\"fa " <> icon <> " fa-fw m-r-sm\"> </i>" <>
             desc <>
        "  </a>" <>
        "</li>"
      else
        ""
      end
    end

    "<td class=\"text-center\">" <>
    "  <div class=\"dropdown\">" <>
    "    <label class=\"dropdown-toggle\" data-toggle=\"dropdown\">" <>
    "      <input type=\"checkbox\" class=\"o-c bars\">" <>
    "    </label>" <>
    "    <ul class=\"dropdown-menu\" style=\"right: 0; left: auto;\">" <>
          Enum.join(dropdowns) <>
    "    </ul>" <>
    "  </div>" <>
    "</td>"
  end
end
