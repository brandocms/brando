defmodule Brando.HTML.Inspect do
  import Brando.Images.Helpers
  import Brando.HTML
  @doc """
  Inspects and displays `model`
  """
  def model(model) do
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

  defp do_inspect_field(name, Ecto.DateTime, nil) do
    ~s(<tr><td>#{name}</td><td><em>Ingen verdi<em></td></tr>)
  end

  defp do_inspect_field(name, Ecto.DateTime, value) do
    require Logger
    Logger.debug(inspect(value))
    ~s(<tr><td>#{name}</td><td>#{value.day}/#{value.month}/#{value.year} #{value.hour}:#{Ecto.DateTime.Util.zero_pad(value.min, 2)}</td></tr>)
  end

  defp do_inspect_field(name, Brando.Type.Role, value) do
    ~s(<tr><td>#{name}</td><td>#{inspect(value)}</td></tr>)
  end

  defp do_inspect_field(name, Brando.Type.Json, value) do
    ~s(<tr><td>#{name}</td><td><em>Kodet verdi</em></td></tr>)
  end

  defp do_inspect_field(name, Brando.Type.Image, nil) do
    ~s(<tr><td>#{name}</td><td><em>Inget tilknyttet bilde</em></td></tr>)
  end

  defp do_inspect_field(name, Brando.Type.Image, value) do
    ~s(<tr><td>#{name}</td><td><div class="imageserie m-b-md"><img src="#{media_url(img(value, :thumb))}" style="padding-bottom: 3px;" /></div></td></tr>)
  end

  defp do_inspect_field(name = "Passord", :string, _value) do
    ~s(<tr><td>#{name}</td><td><em>** sensurert **</em></td></tr>)
  end

  defp do_inspect_field(name, :string, nil) do
    ~s(<tr><td>#{name}</td><td><em>Ingen verdi</em></td></tr>)
  end

  defp do_inspect_field(name, :string, "") do
    ~s(<tr><td>#{name}</td><td><em>Ingen verdi</em></td></tr>)
  end

  defp do_inspect_field(name, :string, value) do
    ~s(<tr><td>#{name}</td><td>#{value}</td></tr>)
  end

  defp do_inspect_field(name, :integer, value) do
    ~s(<tr><td>#{name}</td><td>#{value}</td></tr>)
  end

  defp do_inspect_field(name, :boolean, :true) do
    ~s(<tr><td>#{name}</td><td><i class="fa fa-check text-success"></i></td></tr>)
  end

  defp do_inspect_field(name, :boolean, nil) do
    ~s(<tr><td>#{name}</td><td><i class="fa fa-times text-danger"></i></td></tr>)
  end


  defp do_inspect_field(name, _type, value) do
    require Logger
    Logger.debug(inspect(_type))
    ~s(<tr><td>#{name}</td><td>#{inspect(value)}</td></tr>)
  end

  defp inspect_assoc(name, module, type, value) do
    do_inspect_assoc(translate_field(module, name), type, value)
  end

  defp do_inspect_assoc(name, %Ecto.Association.BelongsTo{} = type, value) do
    ~s(<tr><td>#{name}</td><td>#{type.assoc.__str__(value)}</td></tr>)
  end
  defp do_inspect_assoc(name, %Ecto.Association.Has{}, %Ecto.Association.NotLoaded{}) do
    ~s(<tr><td>#{name}</td><td>Assosiasjonene er ikke hentet.</td></tr>)
  end
  defp do_inspect_assoc(name, %Ecto.Association.Has{}, []) do
    ~s(<tr><td>#{name}</td><td>Ingen assosiasjoner.</td></tr>)
  end
  defp do_inspect_assoc(_name, %Ecto.Association.Has{} = type, value) do
    rows = Enum.map(value, fn (row) -> ~s(<div class="assoc #{type.field}">#{type.assoc.__str__(row)}</div>) end)
    ~s(<tr><td><i class='fa fa-link'></i> Tilknyttede #{type.assoc.__name__(:plural)}</td><td>#{rows}</td></tr>)
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
end