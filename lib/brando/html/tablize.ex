defmodule Brando.HTML.Tablize do
  @moduledoc """
  Displays model data as a table.
  """

  import Brando.HTML, only: [check_or_x: 1, zero_pad: 1]
  import Brando.HTML.Inspect, only: [inspect_field: 3, translate_field: 2]
  import Phoenix.HTML.Tag, only: [content_tag: 3, content_tag: 2]

  @doc """
  Converts `records` into a formatted table with dropdown menus.

  ## Example

      tablize(@users,
              [{"Vis bruker", "fa-search", @conn, :admin_user_path, :show, :id},
               {"Endre bruker", "fa-edit", @conn, :admin_user_path, :edit, :id},
               {"Slett bruker", "fa-trash", @conn, :admin_user_path, :delete_confirm, :id}],
               check_or_x: [:avatar], hide: [:password, :last_login, :inserted_at])

  ## Arguments

    * `records` - List of records to render
    * `dropdowns` - List of dropdowns in format:
                    {display_name, icon, conn, helper_path, action, identifier or nil}

  ## Options

    * `check_or_x` - Provide a list of fields that should be presented
                     with an X or a checkmark.
    * `hide` - List of fields that should not be rendered.

  """
  def tablize([], _, _), do: "Empty"
  def tablize(nil, _, _), do: "Nil"
  def tablize(records, dropdowns, opts) do
    module = List.first(records).__struct__
    table_header = render_thead(module.__fields__, module, opts)
    table_body = render_tbody(module.__fields__, records, module, dropdowns, opts)
    content_tag :table, class: "table table-striped" do
      {:safe, "#{table_header}#{table_body}"}
    end
  end

  defp render_tbody(fields, records, module, dropdowns, opts) do
    rendered_trs = records
      |> Enum.map(&(do_tr(fields, &1, module, dropdowns, opts)))
      |> Enum.join
    "<tbody>#{rendered_trs}</tbody>"
  end

  defp do_tr(fields, record, module, dropdowns, opts) do
    tr_content = fields
      |> Enum.map(&(do_td(&1, record, module.__schema__(:field, &1), opts)))
      |> Enum.join
    "<tr>#{tr_content}#{render_dropdowns(dropdowns, record)}</tr>"
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

  defp do_th(field, module, nil) do
    ~s(<th>#{translate_field(module, field)}</th>)
  end

  defp do_th(field, module, hidden_fields) do
    unless field in hidden_fields do
      ~s(<th>#{translate_field(module, field)}</th>)
    end
  end

  defp render_dropdowns(dropdowns, record) do
    dropdowns = for dropdown <- dropdowns do
      {desc, icon, conn, helper, action, param} = dropdown
      params = if param != nil, do: [conn, action, record], else: [conn, action]
      url = apply(Brando.HTML.helpers(conn), helper, params)
      """
      <li>
        <a href="#{url}">
          <i class="fa #{icon} fa-fw m-r-sm"> </i>
          #{desc}
        </a>
      </li>
      """
    end
    """
    <td class="text-center">
      <div class="dropdown">
        <a class="dropdown-toggle ddbutton" data-toggle="dropdown">
          <i class="fa fa-bars"></i>
        </a>
        <ul class="dropdown-menu" style="right: 0; left: auto;">
          #{dropdowns}
        </ul>
      </div>
    </td>
    """
  end
end