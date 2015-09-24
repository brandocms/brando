defmodule Brando.HTML.Inspect do
  @moduledoc """
  Rendering functions for displaying model data
  """
  use Linguist.Vocabulary

  import Brando.Render, only: [r: 1]
  import Brando.Utils, only: [media_url: 0, img_url: 3]
  import Ecto.DateTime.Utils, only: [zero_pad: 2]
  import Phoenix.HTML.Tag, only: [content_tag: 3, content_tag: 2]

  @doc """
  Returns the record's model name from __name__/1
  `form` is `:singular` or `:plural`
  """
  @spec model_name(String.t, Struct.t, :singular | :plural) :: String.t
  def model_name(language, record, form) do
    record.__struct__.__name__(language, form)
  end

  @doc """
  Returns the model's representation from __repr__/0
  """
  @spec model_repr(String.t, Struct.t) :: String.t
  def model_repr(language, record) do
    record.__struct__.__repr__(language, record)
  end

  @doc """
  Looks up `field` in `module` for Linguist translations
  """
  def translate_field(language, module, field) do
    module.t!(language, "model." <> to_string(field))
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
  def model(_language, nil) do
    ""
  end

  @doc """
  Inspects and displays `model`
  """
  def model(language, model) do
    module = model.__struct__
    fields = module.__schema__(:fields)
    assocs = module.__schema__(:associations)

    rendered_fields = fields
    |> Enum.map(&(render_inspect_field(language, &1, module, module.__schema__(:type, &1), Map.get(model, &1))))
    |> Enum.join

    rendered_assocs = assocs
    |> Enum.map(&(render_inspect_assoc(language, &1, module, module.__schema__(:association, &1), Map.get(model, &1))))
    |> Enum.join

    content_tag :table, class: "table data-table" do
      {:safe, "#{rendered_fields}#{rendered_assocs}"}
    end
  end

  defp render_inspect_field(language, name, module, type, value) do
    if not String.ends_with?(to_string(name), "_id") and not name in module.__hidden_fields__ do
      val = inspect_field(language, name, type, value)
      """
      <tr>
        <td>#{translate_field(language, module, name)}</td>
        <td>#{val}</td>
      </tr>
      """
    end
  end

  @doc """
  Public interface to field inspection
  """
  def inspect_field(language \\ "no", name, type, value) do
    do_inspect_field(language, name, type, value)
  end

  defp do_inspect_field(language, _name, Ecto.DateTime, nil) do
    ~s(<em>#{t!(language, "no_value")}<em>)
  end

  defp do_inspect_field(_language, _name, Ecto.DateTime, value) do
    ~s(#{value.day}/#{value.month}/#{value.year} #{zero_pad(value.hour, 2)}:#{zero_pad(value.min, 2)})
  end

  defp do_inspect_field(language, _name, Ecto.Date, nil) do
    ~s(<em>#{t!(language, "no_value")}<em>)
  end

  defp do_inspect_field(_language, _name, Ecto.Date, value) do
    ~s(#{value.day}/#{value.month}/#{value.year})
  end

  defp do_inspect_field(_language, _name, Brando.Type.Role, roles) do
    roles = Enum.map roles, fn (role) ->
      role_name =
        case role do
          :superuser -> "super"
          :admin -> "admin"
          :staff -> "staff"
        end
      ~s(<span class="label label-#{role}">#{role_name}</span>)
    end
    ~s(#{roles})
  end

  defp do_inspect_field(language, _name, Brando.Type.Json, _value) do
    ~s(<em>#{t!(language, "encoded_value")}</em>)
  end

  defp do_inspect_field(language, _name, Brando.Type.Image, nil) do
    ~s(<em>#{t!(language, "no_connected_image")}</em>)
  end

  defp do_inspect_field(language, _name, Brando.Type.ImageConfig, _value) do
    ~s(<em>#{t!(language, "config_data")}</em>)
  end

  defp do_inspect_field(_language, _name, Brando.Type.Image, value) do
    ~s(<div class="imageserie m-b-md"><img src="#{img_url(value, :thumb, prefix: media_url())}" style="padding-bottom: 3px;" /></div>)
  end

  defp do_inspect_field(language, _name, Brando.Type.Status, value) do
    status =
      case value do
        :published -> Brando.Admin.LayoutView.t!(language, "status.published")
        :pending   -> Brando.Admin.LayoutView.t!(language, "status.pending")
        :draft     -> Brando.Admin.LayoutView.t!(language, "status.draft")
        :deleted   -> Brando.Admin.LayoutView.t!(language, "status.deleted")
      end
    ~s(<span class="label label-#{value}">#{status}</span>)
  end

  defp do_inspect_field(language, :password, :string, _value) do
    ~s(<em>#{t!(language, "censored_value")}</em>)
  end

  defp do_inspect_field(_language, :language, :string, language_code) do
    ~s(<div class="text-center"><img src="#{Brando.helpers.static_path(Brando.endpoint, "/images/brando/blank.gif")}" class="flag flag-#{language_code}" alt="#{language_code}" /></div>)
  end

  defp do_inspect_field(_language, :key, :string, nil) do
    ""
  end
  defp do_inspect_field(_language, :key, :string, val) do
    split = String.split(val, "/", parts: 2)
    if Enum.count(split) == 1 do
      ~s(<strong>#{split}</strong>)
    else
      [main, rest] = split
      ~s(<strong>#{main}</strong>/#{rest})
    end
  end

  defp do_inspect_field(language, _name, :string, nil) do
    ~s(<em>#{t!(language, "encoded_value")}</em>)
  end

  defp do_inspect_field(language, _name, :string, "") do
    ~s(<em>#{t!(language, "no_value")}</em>)
  end

  defp do_inspect_field(_language, _name, :string, value), do: value
  defp do_inspect_field(_language, _name, :integer, value), do: value

  defp do_inspect_field(_language, _name, :boolean, :true) do
    ~s(<div class="text-center"><i class="fa fa-check text-success"></i></div>)
  end

  defp do_inspect_field(_language, _name, :boolean, nil) do
    ~s(<div class="text-center"><i class="fa fa-times text-danger"></i></div>)
  end

  defp do_inspect_field(_language, _name, :boolean, :false) do
    ~s(<div class="text-center"><i class="fa fa-times text-danger"></i></div>)
  end

  defp do_inspect_field(_language, _name, _type, %Brando.User{} = user) do
    r(user)
  end

  defp do_inspect_field(language, _name, nil, %{__struct__: _struct} = value) when is_map(value) do
    model_repr(language, value)
  end

  defp do_inspect_field(_language, _name, _type, value) do
    inspect(value)
  end

  #
  # Associations

  defp render_inspect_assoc(language, name, module, type, value) do
    inspect_assoc(language, translate_field(language, module, name), type, value)
  end

  @doc """
  Public interface to inspect model associations
  """
  def inspect_assoc(language, name, type, value) do
    do_inspect_assoc(language, name, type, value)
  end

  defp do_inspect_assoc(language, name, %Ecto.Association.BelongsTo{}, nil) do
    ~s(<tr><td>#{name}</td><td><em>#{t!(language, "empty_assoc")}</em></td></tr>)
  end
  defp do_inspect_assoc(language, name, %Ecto.Association.BelongsTo{} = type, value) do
    ~s(<tr><td>#{name}</td><td>#{type.related.__repr__(language, value)}</td></tr>)
  end
  defp do_inspect_assoc(language, name, %Ecto.Association.Has{}, %Ecto.Association.NotLoaded{}) do
    ~s(<tr><td>#{name}</td><td>#{t!(language, "assoc_not_fetched")}</td></tr>)
  end
  defp do_inspect_assoc(language, name, %Ecto.Association.Has{}, []) do
    ~s(<tr><td>#{name}</td><td><em>#{t!(language, "empty_assoc")}</em></td></tr>)
  end
  defp do_inspect_assoc(language, _name, %Ecto.Association.Has{} = type, value) do
    rows = Enum.map(value, fn (row) -> ~s(<div class="assoc #{type.field}">#{type.related.__repr__(language, row)}</div>) end)
    ~s(<tr><td><i class='fa fa-link'></i> #{t!(language, "connected")} #{type.related.__name__(language, :plural)}</td><td>#{rows}</td></tr>)
  end

  locale "en", [
    encoded_value: "encoded value",
    no_value: "no value",
    censored_value: "** censored **",
    empty_assoc: "no associations",
    assoc_not_fetched: "association not fetched",
    connected: "Connected",
    config_data: "Configuration data",
    no_connected_image: "No connected image"
  ]

  locale "no", [
    encoded_value: "kodet verdi",
    no_value: "ingen verdi",
    censored_value: "** sensurert **",
    empty_assoc: "ingen assosiasjoner",
    assoc_not_fetched: "Assosiasjonene er ikke hentet.",
    connected: "Tilknyttet",
    config_data: "Konfigurasjonsdata",
    no_connected_image: "Inget tilknyttet bilde"
  ]
end
