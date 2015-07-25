defmodule Brando.HTML.Inspect do
  @moduledoc """
  Rendering functions for displaying model data
  """

  import Brando.HTML
  import Brando.Render, only: [r: 1]
  import Ecto.DateTime.Util, only: [zero_pad: 2]
  import Phoenix.HTML.Tag, only: [content_tag: 3, content_tag: 2]

  @doc """
  Returns the record's model name from __name__/1
  `form` is `:singular` or `:plural`
  """
  @spec model_name(Struct.t, :singular | :plural) :: String.t
  def model_name(record, form) do
    record.__struct__.__name__(form)
  end

  @doc """
  Returns the model's representation from __repr__/0
  """
  def model_repr(record) do
    record.__struct__.__repr__(record)
  end

  @doc """
  Looks up `field` in `module` for Linguist translations
  """
  def translate_field(module, field) do
    module.t!("no", "model." <> to_string(field))
  end

  @doc """
  Inspects and displays `model`
  """
  def model(nil) do
    ""
  end
  @doc """
  Inspects and displays `model`
  """
  def model(model) do
    module = model.__struct__
    fields = module.__schema__(:fields)
    assocs = module.__schema__(:associations)

    rendered_fields = fields
    |> Enum.map(&(render_inspect_field(&1, module, module.__schema__(:type, &1), Map.get(model, &1))))
    |> Enum.join

    rendered_assocs = assocs
    |> Enum.map(&(render_inspect_assoc(&1, module, module.__schema__(:association, &1), Map.get(model, &1))))
    |> Enum.join

    content_tag :table, class: "table data-table" do
      {:safe, "#{rendered_fields}#{rendered_assocs}"}
    end
  end

  defp render_inspect_field(name, module, type, value) do
    if not String.ends_with?(to_string(name), "_id") and not name in module.__hidden_fields__ do
      val = inspect_field(name, type, value)
      """
      <tr>
        <td>#{translate_field(module, name)}</td>
        <td>#{val}</td>
      </tr>
      """
    end
  end

  @doc """
  Public interface to field inspection
  """
  def inspect_field(name, type, value) do
    do_inspect_field(name, type, value)
  end

  defp do_inspect_field(_name, Ecto.DateTime, nil) do
    ~s(<em>Ingen verdi<em>)
  end

  defp do_inspect_field(_name, Ecto.DateTime, value) do
    ~s(#{value.day}/#{value.month}/#{value.year} #{zero_pad(value.hour, 2)}:#{zero_pad(value.min, 2)})
  end

  defp do_inspect_field(_name, Brando.Type.Role, roles) do
    roles = Enum.map roles, fn (role) ->
      role_name =
        case role do
          :superuser -> "superbruker"
          :admin -> "admin"
          :staff -> "stab"
        end
      ~s(<span class="label label-#{role}">#{role_name}</span>)
    end
    ~s(#{roles})
  end

  defp do_inspect_field(_name, Brando.Type.Json, _value) do
    ~s(<em>Kodet verdi</em>)
  end

  defp do_inspect_field(_name, Brando.Type.Image, nil) do
    ~s(<em>Inget tilknyttet bilde</em>)
  end

  defp do_inspect_field(_name, Brando.Type.ImageConfig, _value) do
    ~s(<em>Konfigurasjonsdata</em>)
  end

  defp do_inspect_field(_name, Brando.Type.Image, value) do
    ~s(<div class="imageserie m-b-md"><img src="#{media_url(img(value, :thumb))}" style="padding-bottom: 3px;" /></div>)
  end

  defp do_inspect_field(_name, Brando.Type.Status, value) do
    status =
      case value do
        :published -> "publisert"
        :pending   -> "venter"
        :draft     -> "utkast"
        :deleted   -> "slettet"
      end
    ~s(<span class="label label-#{value}">#{status}</span>)
  end

  defp do_inspect_field(:password, :string, _value) do
    ~s(<em>** sensurert **</em>)
  end

  defp do_inspect_field(:language, :string, language_code) do
    ~s(<div class="text-center"><img src="#{Brando.get_helpers.static_path(Brando.get_endpoint, "/images/brando/blank.gif")}" class="flag flag-#{language_code}" alt="#{language_code}" /></div>)
  end

  defp do_inspect_field(:key, :string, val) do
    split = String.split(val, "/", parts: 2)
    if Enum.count(split) == 1 do
      ~s(<strong>#{split}</strong>)
    else
      [main, rest] = split
      ~s(<strong>#{main}</strong>/#{rest})
    end
  end

  defp do_inspect_field(_name, :string, nil) do
    ~s(<em>Ingen verdi</em>)
  end

  defp do_inspect_field(_name, :string, "") do
    ~s(<em>Ingen verdi</em>)
  end

  defp do_inspect_field(_name, :string, value), do: value
  defp do_inspect_field(_name, :integer, value), do: value

  defp do_inspect_field(_name, :boolean, :true) do
    ~s(<div class="text-center"><i class="fa fa-check text-success"></i></div>)
  end

  defp do_inspect_field(_name, :boolean, nil) do
    ~s(<div class="text-center"><i class="fa fa-times text-danger"></i></div>)
  end

  defp do_inspect_field(_name, :boolean, :false) do
    ~s(<div class="text-center"><i class="fa fa-times text-danger"></i></div>)
  end

  defp do_inspect_field(_name, _type, %Brando.User{} = user) do
    r(user)
  end

  defp do_inspect_field(_name, nil, %{__struct__: _struct} = value) when is_map(value) do
    model_repr(value)
  end

  defp do_inspect_field(_name, _type, value) do
    inspect(value)
  end

  #
  # Associations

  defp render_inspect_assoc(name, module, type, value) do
    inspect_assoc(translate_field(module, name), type, value)
  end

  @doc """
  Public interface to inspect model associations
  """
  def inspect_assoc(name, type, value) do
    do_inspect_assoc(name, type, value)
  end

  defp do_inspect_assoc(name, %Ecto.Association.BelongsTo{}, nil) do
    ~s(<tr><td>#{name}</td><td><em>Ingen assosiasjoner.</em></td></tr>)
  end
  defp do_inspect_assoc(name, %Ecto.Association.BelongsTo{} = type, value) do
    ~s(<tr><td>#{name}</td><td>#{type.assoc.__repr__(value)}</td></tr>)
  end
  defp do_inspect_assoc(name, %Ecto.Association.Has{}, %Ecto.Association.NotLoaded{}) do
    ~s(<tr><td>#{name}</td><td>Assosiasjonene er ikke hentet.</td></tr>)
  end
  defp do_inspect_assoc(name, %Ecto.Association.Has{}, []) do
    ~s(<tr><td>#{name}</td><td><em>Ingen assosiasjoner.</em></td></tr>)
  end
  defp do_inspect_assoc(_name, %Ecto.Association.Has{} = type, value) do
    rows = Enum.map(value, fn (row) -> ~s(<div class="assoc #{type.field}">#{type.assoc.__repr__(row)}</div>) end)
    ~s(<tr><td><i class='fa fa-link'></i> Tilknyttede #{type.assoc.__name__(:plural)}</td><td>#{rows}</td></tr>)
  end
end