defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions. Imported in Brando.AdminView.
  """

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.HTML
    end
  end

  @doc """
  Returns the application name set in config.exs
  """
  def app_name do
    Brando.config(:app_name)
  end

  @doc """
  Returns the Helpers module from the router.
  """
  def helpers(conn) do
    Phoenix.Controller.router_module(conn).__helpers__
  end

  @doc """
  Creates an URL from a menu item.

  ## Example

      iex> menu_url(conn, {:admin_user_path, :new})

  """
  def menu_url(conn, {fun, action}) do
    apply(helpers(conn), fun, [conn, action])
  end

  @doc """
  Checks if `conn`'s `full_path` matches `current_path`.
  Returns "active", or "".
  """
  def active_path(conn, url_to_match) do
    if Plug.Conn.full_path(conn) == url_to_match, do: "active", else: ""
  end

  @doc """
  Formats `arg1` (Ecto.DateTime) as a binary.
  """
  def format_date(%Ecto.DateTime{year: year, month: month, day: day}) do
    "#{day}/#{month}/#{year}"
  end

  @doc """
  Return DATE ERROR if `_erroneus_date` is not an Ecto.DateTime
  """
  def format_date(_erroneus_date) do
    ">>DATE ERROR<<"
  end

  @doc """
  Zero pad `int` as a binary.

  ## Example

      iex> zero_pad(5)
      "005"

  """
  def zero_pad(int) do
    String.rjust(Integer.to_string(int), 3, ?0)
  end

  @doc """
  Split `full_name` and return first name
  """
  def first_name(full_name) do
    full_name
    |> String.split
    |> hd
  end

  @doc """
  Return the current user set in session.
  """
  def current_user(conn) do
    Plug.Conn.get_session(conn, :current_user)
  end

  @doc """
  Return joined path of `file` and the :media_url config option
  as set in your app's config.exs.
  """
  def media_url(file) do
    Path.join([Brando.config(:media_url), file])
  end

  @doc """
  Return joined path of `file` and the :static_url config option
  as set in your app's config.exs.
  """
  def static_url(file) do
    Path.join([Brando.config(:static_url), file])
  end

  @doc """
  If any javascripts have been assigned to :js_extra on `conn`,
  render each as a <script> tag. If nil, do nothing.
  To assign to `:js_extra`, use `Brando.Utils.add_js/2`
  """
  def js_extra(conn) do
    do_js_extra(conn.assigns[:js_extra])
  end

  defp do_js_extra(nil), do: ""
  defp do_js_extra(js) when is_list(js) do
    for j <- js, do: do_js_extra(j)
  end
  defp do_js_extra(js), do: Phoenix.HTML.safe(~s(<script type="text/javascript" src="#{static_url(js)}" charset="utf-8"></script>))

  @doc """
  If any css files have been assigned to :css_extra on `conn`,
  render each as a <link> tag. If nil, do nothing.
  To assign to `:css_extra`, use `Brando.Utils.add_css/2`
  """
  def css_extra(conn) do
    do_css_extra(conn.assigns[:css_extra])
  end

  defp do_css_extra(nil), do: ""
  defp do_css_extra(css) when is_list(css) do
    for c <- css, do: do_css_extra(c)
  end
  defp do_css_extra(css), do: Phoenix.HTML.safe(~s(<link rel="stylesheet" href="#{static_url(css)}">))

  @doc """
  Inspects and displays `model`
  """
  def inspect_model(model) do
    module = model.__struct__
    fields = module.__schema__(:fields)
    assocs = module.__schema__(:associations)
    rendered_fields = Enum.join(Enum.map(fields, fn (field) -> inspect_field(field, module, module.__schema__(:field, field), Map.get(model, field)) end))
    rendered_assocs = Enum.join(Enum.map(assocs, fn (assoc) -> inspect_assoc(assoc, module, module.__schema__(:association, assoc), Map.get(model, assoc)) end))
    Phoenix.HTML.safe(~s(<table class="table data-table">#{rendered_fields}#{rendered_assocs}</table>))
  end

  defp inspect_field(name, module, type, value) do
    unless String.ends_with?(to_string(name), "_id"), do:
      do_inspect_field(translate_field(module, name), type, value)
  end

  defp do_inspect_field(name, Ecto.DateTime, value) do
    ~s(<tr><td>#{name}</td><td>#{value.day}/#{value.month}/#{value.year} #{value.hour}:#{value.min}</td></tr>)
  end
  defp do_inspect_field(name, _type, value) do
    ~s(<tr><td>#{name}</td><td>#{value}</td></tr>)
  end

  defp inspect_assoc(name, module, type, value) do
    do_inspect_assoc(translate_field(module, name), type, value)
  end

  defp do_inspect_assoc(name, %Ecto.Associations.BelongsTo{} = type, value) do
    ~s(<tr><td>#{name}</td><td>#{type.assoc.__str__(value)}</td></tr>)
  end
  defp do_inspect_assoc(name, %Ecto.Associations.Has{}, %Ecto.Associations.NotLoaded{}) do
    ~s(<tr><td>#{name}</td><td>Assosiasjonene er ikke hentet.</td></tr>)
  end
  defp do_inspect_assoc(name, %Ecto.Associations.Has{}, []) do
    ~s(<tr><td>#{name}</td><td>Ingen assosiasjoner.</td></tr>)
  end
  defp do_inspect_assoc(_name, %Ecto.Associations.Has{} = type, value) do
    Enum.map(value, fn (row) -> ~s(<tr><td><i class='fa fa-link'></i> Tilknyttet #{type.assoc.__name__(:singular)}</td><td>#{type.assoc.__str__(row)}</td></tr>) end)
  end

  @doc """
  Returns the record's model name from __name__/1
  `form` is `:singular` or `:plural`
  """
  @spec model_name(Struct.t, :singular | :plural) :: String.t
  def model_name(record, form) do
    record.__struct__.__name__(form)
  end

  @doc """
  Returns the model's representation from __str__/0
  """
  def model_str(record) do
    record.__struct__.__str__(record)
  end

  defp translate_field(module, field) do
    module.t!("no", "model." <> to_string(field))
  end

  def delete_form_button(record, helper) do
    action = Brando.Form.get_action(helper, :delete)
    Phoenix.HTML.safe("""
    <form method="POST" action="#{action}">
      <input type="hidden" name="_method" value="delete" />
      <input type="hidden" name="id" value="#{record.id}" />
      <button class="btn btn-danger">
        <i class="fa fa-trash-o m-r-sm"> </i>
        Slett
      </button>
    </form>
    """)
  end

end