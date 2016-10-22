defmodule Brando.HTML.Inspect do
  @moduledoc """
  Rendering functions for displaying schema data
  """
  import Brando.Gettext
  import Brando.Render, only: [r: 1]
  import Brando.HTML, only: [zero_pad: 2]
  import Brando.Utils, only: [media_url: 0, img_url: 3]
  import Phoenix.HTML.Tag, only: [content_tag: 3]

  @doc """
  Returns the record's schema name from __name__/1
  `form` is `:singular` or `:plural`
  """
  @spec schema_name(map, :singular | :plural) :: String.t
  def schema_name(record, form) do
    record.__struct__.__name__(form)
  end

  @doc """
  Returns the schema's representation from __repr__/0
  """
  @spec schema_repr(map) :: String.t
  def schema_repr(record) do
    record.__struct__.__repr__(record)
  end

  @doc """
  Inspects and displays `schema`
  """
  def schema(nil) do
    ""
  end

  @doc """
  Inspects and displays `schema_struct`
  """
  def schema(schema_struct) do
    module = schema_struct.__struct__
    fields = module.__schema__(:fields)
    assocs = module.__schema__(:associations)

    rendered_fields =
      fields
      |> Enum.map(&(render_inspect_field(&1, module, module.__schema__(:type, &1),
                                         Map.get(schema_struct, &1))))
      |> Enum.join

    rendered_assocs =
      assocs
      |> Enum.map(&(render_inspect_assoc(&1, module, module.__schema__(:association, &1),
                                         Map.get(schema_struct, &1))))
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
        <td>#{module.__field__(name)}</td>
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

  defp do_inspect_field(_name, :naive_datetime, nil) do
    ~s(<em>#{gettext("No value")}<em>)
  end

  defp do_inspect_field(_name, :naive_datetime, value) do
    ~s(#{value.day}/#{value.month}/#{value.year} #{zero_pad(value.hour, 2)}:#{zero_pad(value.minute, 2)})
  end

  defp do_inspect_field(_name, :date, nil) do
    ~s(<em>#{gettext("No value")}<em>)
  end

  defp do_inspect_field(_name, :date, value) do
    ~s(#{value.day}/#{value.month}/#{value.year})
  end

  defp do_inspect_field(_name, Brando.Type.Role, roles) do
    Enum.map roles, fn (role) ->
      role_name =
        case role do
          :superuser -> gettext("superuser")
          :admin     -> gettext("admin")
          :staff     -> gettext("staff")
        end
      ~s(<span class="label label-#{role}">#{role_name}</span>)
    end
  end

  defp do_inspect_field(_name, Brando.Type.Json, _value) do
    ~s(<em>#{gettext("Encoded value")}</em>)
  end

  defp do_inspect_field(_name, Brando.Type.Image, nil) do
    ~s(<em>#{gettext("No connected image")}</em>)
  end

  defp do_inspect_field(_name, Brando.Type.ImageConfig, _value) do
    ~s(<em>#{gettext("Configuration data")}</em>)
  end

  defp do_inspect_field(_name, Brando.Type.Image, value) do
    ~s(<div class="imageserie m-b-md">
         <img src="#{img_url(value, :thumb, prefix: media_url())}" style="padding-bottom: 3px;" />
       </div>)
  end

  defp do_inspect_field(_name, Brando.Type.File, nil) do
    ~s(<em>#{gettext("No connected file")}</em>)
  end

  defp do_inspect_field(_name, Brando.Type.File, value) do
    ~s(<i class="fa fa-file m-r-sm"> </i> #{value.path})
  end

  defp do_inspect_field(_name, Brando.Type.Status, value) do
    status =
      case value do
        :published -> gettext("Published")
        :pending   -> gettext("Pending")
        :draft     -> gettext("Draft")
        :deleted   -> gettext("Deleted")
      end
    ~s(<span class="label label-#{value}">#{status}</span>)
  end

  defp do_inspect_field(:password, :string, _value) do
    ~s(<em>#{gettext("** censored **")}</em>)
  end

  defp do_inspect_field(:language, :string, language_code) do
    """
    <div class="text-center">
      <img src="#{Brando.helpers.static_path(Brando.endpoint, "/images/brando/blank.gif")}"
           class="flag flag-#{language_code}" alt="#{language_code}" />
    </div>
    """
  end

  defp do_inspect_field(:key, :string, nil) do
    ""
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
    ~s(<em>#{gettext("No value")}</em>)
  end

  defp do_inspect_field(_name, :string, "") do
    ~s(<em>#{gettext("No value")}</em>)
  end

  defp do_inspect_field(:slug, :string, value) do
    ~s(<span class="text-mono">#{value}</span>)
  end

  defp do_inspect_field(_name, :string, value), do: value
  defp do_inspect_field(_name, :integer, value), do: value

  defp do_inspect_field(_name, :boolean, :true) do
    ~s(<div class="text-center"><i class="icon-centered fa fa-check text-success"></i></div>)
  end

  defp do_inspect_field(_name, :boolean, nil) do
    ~s(<div class="text-center"><i class="icon-centered fa fa-times text-danger"></i></div>)
  end

  defp do_inspect_field(_name, :boolean, :false) do
    ~s(<div class="text-center"><i class="icon-centered fa fa-times text-danger"></i></div>)
  end

  defp do_inspect_field(_name, _type, %Brando.User{} = user) do
    r(user)
  end

  defp do_inspect_field(_name, nil, %{__struct__: _struct} = value)
  when is_map(value) do
    schema_repr(value)
  end

  defp do_inspect_field(_name, _type, value) do
    inspect(value)
  end

  #
  # Associations

  defp render_inspect_assoc(name, module, type, value) do
    inspect_assoc(module.__field__(name), type, value)
  end

  @doc """
  Public interface to inspect schema associations
  """
  def inspect_assoc(name, type, value) do
    do_inspect_assoc(name, type, value)
  end

  defp do_inspect_assoc(name, %Ecto.Association.BelongsTo{}, nil) do
    ~s(<tr><td>#{name}</td><td><em>#{gettext("Empty association")}</em></td></tr>)
  end
  defp do_inspect_assoc(name, %Ecto.Association.BelongsTo{} = type, value) do
    ~s(<tr><td>#{name}</td><td>#{type.related.__repr__(value)}</td></tr>)
  end
  defp do_inspect_assoc(name, %Ecto.Association.Has{}, %Ecto.Association.NotLoaded{}) do
    ~s(<tr><td>#{name}</td><td>#{gettext("Association not fetched")}</td></tr>)
  end
  defp do_inspect_assoc(name, %Ecto.Association.Has{}, []) do
    ~s(<tr><td>#{name}</td><td><em>#{gettext("Empty association")}</em></td></tr>)
  end
  defp do_inspect_assoc(_name, %Ecto.Association.Has{} = type, value) do
    rows =
      Enum.map value, fn (row) ->
        """
        <div class="assoc #{type.field}">
          #{type.related.__repr__(row)}
        </div>
        """
      end
    """
    <tr>
      <td>
        <i class="fa fa-link"></i>
        #{gettext("Connected")} #{type.related.__name__(:plural)}
      </td>
      <td>
        #{rows}
      </td>
    </tr>
    """
  end
end
