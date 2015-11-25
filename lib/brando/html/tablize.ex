defmodule Brando.HTML.Tablize do
  @moduledoc """
  Displays model data as a table.
  """

  @type dropdown :: {String.t, String.t, atom, atom, atom | [atom]}

  import Brando.Gettext
  import Brando.HTML, only: [check_or_x: 1, zero_pad: 1, can_render?: 2]
  import Brando.HTML.Inspect, only: [inspect_field: 3]

  @narrow_fields [:language, :id, :status]
  @narrow_types [:integer, :boolean]
  @date_fields [:inserted_at, :updated_at, :published_at, :deleted_at]

  defstruct records: nil,
            module: nil,
            conn: nil,
            dropdowns: nil,
            opts: nil

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

    * `check_or_x` - List of fields displayed as X or checkmark.
    * `children` - Name of field that holds child elements.
    * `hide` - List of fields that should not be rendered.
    * `filter` - Boolean. Implements a filtering input box above table.
    * `split_by` - Split table by field: `split_by: :language`.
    * `colgroup` - Column widths if you need to override.
                   Supply as list: `[100, nil, nil, 200, nil, 200]`

  """
  @spec tablize(Plug.Conn.t, [Type] | [] | nil, dropdown, Keyword.t) :: {:safe, iodata}
  def tablize(_, [], _, _), do: "<p>#{gettext("No results")}</p>" |> Phoenix.HTML.raw
  def tablize(_, nil, _, _), do: "<p>#{gettext("No results")}</p>" |> Phoenix.HTML.raw
  def tablize(conn, records, dropdowns, opts) do
    tablize_opts = %Brando.HTML.Tablize{
      module: List.first(records).__struct__,
      dropdowns: dropdowns,
      records: records,
      conn: conn,
      opts: opts
    }

    colgroup =
      if opts[:colgroup] do
        render_colgroup(:manual, opts[:colgroup])
      else
        render_colgroup(:auto, tablize_opts)
      end

    filter_attr =
      if opts[:filter], do:
        ~s( data-filter-table="true"),
      else: ""

    table_header = render_thead(tablize_opts)
    table_body = render_tbody(tablize_opts)
    table = """
      <table class="table"#{filter_attr}>
        #{colgroup}
        #{table_header}
        #{table_body}
      </table>
      """

    filter =
      if opts[:filter] do
        """
        <div class="filter-input-wrapper pull-right">
          <i class="fa fa-fw fa-search m-r-sm m-l-xs"></i>
          <input type="text" placeholder="Filter" id="filter-input" />
        </div>
        """
      else
        ""
      end
    Phoenix.HTML.raw([filter|table])
  end

  defp render_colgroup(:auto, %{module: module, opts: opts}) do
    fields =
      opts[:hide] && module.__keys__ -- opts[:hide] || module.__keys__

    narrow_fields =
      opts[:check_or_x] && @narrow_fields ++ opts[:check_or_x] || @narrow_fields

    colgroups = for f <- fields do
      type = module.__schema__(:type, f)
      cond do
        type in @narrow_types  -> ~s(<col style="width: 10px;">)
        f in narrow_fields     -> ~s(<col style="width: 10px;">)
        f in @date_fields      -> ~s(<col style="width: 140px;">)
        f == :creator          -> ~s(<col style="width: 180px;">)
        true                   -> ~s(<col>)
      end
    end
    # add expander
    colgroups = [~s(<col style="width: 10px;">)|colgroups]
    # add menu col
    colgroups = colgroups ++ ~s(<col style="width: 80px;">)
    "<colgroup>#{IO.iodata_to_binary(colgroups)}</colgroup>"
  end

  defp render_colgroup(:manual, list) do
    colgroups = for col <- list do
      col && ~s(<col style="width: #{col}px;">) || "<col>"
    end
    colgroups = colgroups ++ ~s(<col style="width: 80px;">)
    "<colgroup>#{IO.iodata_to_binary(colgroups)}</colgroup>"
  end

  defp render_tbody(%{records: records, opts: opts} = tablize_opts) do
    if split_by = opts[:split_by] do
      tbodies =
        for {_, split_recs} <- Brando.Utils.split_by(records, split_by) do
          do_render_tbody(split_recs, tablize_opts)
        end
      Enum.join(tbodies, ~s(<tr class="splitter"><td></td></tr>))
    else
      do_render_tbody(records, tablize_opts)
    end
  end

  defp do_render_tbody(records, tablize_opts) do
    records
    |> Enum.map(&(do_tr(&1, tablize_opts)))
    |> Enum.join
    |> wrap_with("<tbody>", "</tbody>")
  end

  defp wrap_with(content, pre, post) do
    "#{pre}#{content}#{post}"
  end

  defp render_tr_content(record, %{module: module, opts: opts}) do
    module.__keys__
    |> Enum.map(&(do_td(&1, record, module.__schema__(:type, &1), opts)))
    |> Enum.join
  end

  defp render_child_rows(children, parent, tablize_opts) do
    for child <- children do
      tr_content = render_tr_content(child, tablize_opts)
      """
      <tr data-parent-id="#{parent.id}" class="child hidden">
        <td></td>
        #{tr_content}
        #{render_dropdowns(child, tablize_opts)}
      </tr>
      """
    end
  end

  defp render_children(record, %{opts: opts} = tablize_opts) do
    case Map.get(record, opts[:children]) do
      nil -> nil
      [] -> nil
      children ->
        children
        |> render_child_rows(record, tablize_opts)
        |> Enum.join
    end
  end

  defp do_tr(record, tablize_opts) do
    tr_content = render_tr_content(record, tablize_opts)
    children   = render_children(record, tablize_opts)
    expander   = render_expander(record, children)
    dropdowns  = render_dropdowns(record, tablize_opts)
    row = """
    <tr>
      #{expander}
      #{tr_content}
      #{dropdowns}
    </tr>
    """
    children && row <> children || row
  end

  defp do_td(:id, record, _type, _opts) do
    """
    <td data-field="id" class="text-small text-center text-mono text-muted">
      ##{zero_pad(Map.get(record, :id))}
    </td>
    """
  end

  defp do_td(field, record, type, opts) do
    unless field in Keyword.get(opts, :hide, []) do
      if field in Keyword.get(opts, :check_or_x, []) do
        """
        <td data-field="#{field}" class="text-center">
          #{check_or_x(Map.get(record, field))}
        </td>
        """
      else
        """
        <td data-field="#{field}">
          #{inspect_field(field, type, Map.get(record, field))}
        </td>
        """
      end
    end
  end

  defp render_expander(_, nil) do
    "<td></td>"
  end

  defp render_expander(record, _) do
    """
    <td>
      <a href=" class="expand-page-children" data-id="#{record.id}">
        <i class="fa fa-plus"></i>
      </a>
    </td>
    """
  end

  defp render_thead(%{module: module, opts: opts}) do
    fields = module.__keys__
    rendered_ths =
      fields
      |> Enum.map(&(do_th(&1, module, opts[:hide])))
      |> Enum.join

    """
    <thead>
      <tr>
        <th></th>
        #{rendered_ths}
        <th class="text-center">☰</th>
      </tr>
    </thead>
    """
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

  defp render_dropdowns(record, tablize_opts) do
    dropdowns = render_dropdowns_content(record, tablize_opts)
    """
    <td class="text-center">
      <div class="dropdown">
        <label class="dropdown-toggle" data-toggle="dropdown">
          <input type="checkbox" class="o-c bars">
        </label>
        <ul class="dropdown-menu" style="right: 0; left: auto;">
          #{Enum.join(dropdowns)}
        </ul>
      </div>
    </td>
    """
  end

  defp render_dropdowns_content(record, %{conn: conn, dropdowns: dropdowns}) do
    for dropdown <- dropdowns do
      case tuple_size(dropdown) do
        5 -> {desc, icon, helper, action, param} = dropdown
        6 -> {desc, icon, helper, action, param, role} = dropdown
      end

      fun_params = get_function_params(param, record, action)
      url = apply(Brando.helpers, helper, fun_params)

      if can_render?(conn, %{role: role}) do
        """
        <li>
          <a href="#{url}>
            <i class="fa #{icon} fa-fw m-r-sm"> </i>
             #{desc}
          </a>
        </li>
        """
      else
        ""
      end
    end
  end

  defp get_function_params(param, record, action) do
    case param do
      nil -> [Brando.endpoint, action]
      param when is_list(param) ->
        params = Enum.map(param, &Map.get(record, &1))
        [Brando.endpoint, action, params] |> List.flatten
      param ->
        [Brando.endpoint, action, Map.get(record, param)]
    end
  end
end
