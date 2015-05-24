defmodule Brando.HTML.Tablize do
  @moduledoc """
  Displays model data as a table.
  """

  import Brando.HTML, only: [check_or_x: 1, zero_pad: 1]
  import Brando.HTML.Inspect, only: [inspect_field: 3, translate_field: 2]
  import Phoenix.HTML.Tag, only: [content_tag: 3, content_tag: 2]

  @narrow_fields [:language, :id, :status]
  @narrow_types [:integer, :boolean]
  @date_fields [:inserted_at, :updated_at, :published_at, :deleted_at]

  @doc """
  Converts `records` into a formatted table with dropdown menus.

  ## Example

      tablize(@conn, @users,
              [{"Vis bruker", "fa-search", :admin_user_path, :show, :id},
               {"Endre bruker", "fa-edit", :admin_user_path, :edit, :id},
               {"Slett bruker", "fa-trash", :admin_user_path, :delete_confirm, :id}],
               check_or_x: [:avatar], hide: [:password, :last_login, :inserted_at])

  ## Arguments

    * `conn` - a Plug.Conn struct
    * `records` - List of records to render
    * `dropdowns` - List of dropdowns in format:
                    {display_name, icon, helper_path, action, identifier or nil, role or nil}

  ## Options

    * `check_or_x` - Provide a list of fields that should be presented
                     with an X or a checkmark.
    * `hide` - List of fields that should not be rendered.
    * `colgroup` - Column widths if you need to override.
                   Supply as list `[100, nil, nil, 200, nil, 200]`

  """
  def tablize(_, [], _, _), do: "Empty"
  def tablize(_, nil, _, _), do: "Nil"
  def tablize(conn, records, dropdowns, opts) do
    module = List.first(records).__struct__
    if opts[:colgroup] do
      colgroup = render_colgroup(:manual, opts[:colgroup])
    else
      colgroup = render_colgroup(:auto, module, opts)
    end
    table_header = render_thead(module.__fields__, module, opts)
    table_body = render_tbody(module.__fields__, records, module, conn, dropdowns, opts)
    content_tag :table, {:safe, "#{colgroup}#{table_header}#{table_body}"}, class: "table table-striped"
  end

  defp render_colgroup(:auto, module, opts) do
    fields = if opts[:hide], do: module.__fields__ -- opts[:hide], else: module.__fields__
    narrow_fields = if opts[:check_or_x], do: @narrow_fields ++ opts[:check_or_x], else: @narrow_fields
    colgroups = for f <- fields do
      type = module.__schema__(:field, f)
      cond do
        type in @narrow_types  -> "<col style=\"width: 10px;\">"
        f in narrow_fields     -> "<col style=\"width: 10px;\">"
        f in @date_fields      -> "<col style=\"width: 140px;\">"
        true                   -> "<col>"
      end
    end
    # add menu col
    colgroups = colgroups ++ "<col style=\"width: 80px;\">"
    "<colgroup>" <> IO.iodata_to_binary(colgroups) <> "</colgroup>"
  end

  defp render_colgroup(:manual, list) do
    colgroups = for col <- list do
      if col, do: "<col style=\"width: #{col}px;\">", else: "<col>"
    end
    colgroups = colgroups ++ "<col style=\"width: 80px;\">"
    "<colgroup>" <> IO.iodata_to_binary(colgroups) <> "</colgroup>"
  end

  defp render_tbody(fields, records, module, conn, dropdowns, opts) do
    rendered_trs =
      records
      |> Enum.map(&(do_tr(fields, &1, module, conn, dropdowns, opts)))
      |> Enum.join
    "<tbody>#{rendered_trs}</tbody>"
  end

  defp do_tr(fields, record, module, conn, dropdowns, opts) do
    tr_content = fields
      |> Enum.map(&(do_td(&1, record, module.__schema__(:field, &1), opts)))
      |> Enum.join
    "<tr>#{tr_content}#{render_dropdowns(conn, dropdowns, record)}</tr>"
  end

  defp do_td(:id, record, _type, _opts) do
    ~s(<td class="text-center text-mono text-muted"><small>##{zero_pad(Map.get(record, :id))}</small></td>)
  end

  defp do_td(field, record, type, opts) do
    unless field in opts[:hide] do
      if field in opts[:check_or_x] do
        ~s(<td class="text-center">#{check_or_x(Map.get(record, field))}</td>)
      else
        ~s(<td>#{inspect_field(field, type, Map.get(record, field))}</td>)
      end
    end
  end

  defp render_thead(fields, module, opts) do
    rendered_ths = fields
      |> Enum.map(&(do_th(&1, module, opts[:hide])))
      |> Enum.join
    ~s(<thead><tr>#{rendered_ths}<th class="text-center">Meny</th></tr></thead>)
  end

  defp do_th(:id, _module, _hidden_fields) do
    ~s(<th class="text-center">&#8470;</th>)
  end

  defp do_th(field, module, hidden_fields) do
    unless field in hidden_fields do
      ~s(<th>#{translate_field(module, field)}</th>)
    end
  end

  defp render_dropdowns(conn, dropdowns, record) do
    dropdowns = for dropdown <- dropdowns do
      case tuple_size(dropdown) do
        5 -> {desc, icon, helper, action, param} = dropdown
        6 -> {desc, icon, helper, action, param, role} = dropdown
      end
      params = if param != nil, do: [Brando.get_endpoint, action, record], else: [Brando.get_endpoint, action]
      url = apply(Brando.get_helpers, helper, params)
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