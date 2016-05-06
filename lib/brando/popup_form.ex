defmodule Brando.PopupForm do
  @moduledoc """
  Helper functions for displaying popup forms from javascript through the system channel.

  ## Usage

  First, register the form in your app's endpoint startup. The first argument is the
  name of the schema, second is the form module and third is a list of fields you want
  returned if repo insertion is successful:

      Brando.PopupForm.Registry.register("client", MyApp.ClientForm, "Create client", [:id, :name])

  Then add javascript to your app:

      import PopupForm from "brando";

      $('.avatar img').click((e) => {
          let clientForm = new PopupForm("client", clientInsertionSuccess);
      });

      function clientInsertionSuccess(fields) {
          // here you'd insert the returned fields into a select or something similar.
          console.log(`${fields.id} --> ${fields.username}`);
      }
  """
  @doc """
  Returns Brando.Form struct for registered popup form `name`
  """
  def create(name, params \\ []) do
    with {:ok, {form_module, _header, _wanted_fields}} <- Brando.PopupForm.Registry.get(name),
         {:ok, changeset}                     <- get_changeset(form_module, %{}),
      do: form_module.get_popup_form(type: :create, action: :create, params: params, changeset: changeset)
  end

  @doc """
  Posts popup form `data` to registered `name`
  """
  def post(name, data) do
    params =
      data
      |> Plug.Conn.Query.decode
      |> Map.get(name)

    {:ok, {form_module, _header, wanted_fields}} = Brando.PopupForm.Registry.get(name)
    {:ok, changeset} = get_changeset(form_module, params)

    case Brando.repo.insert(changeset) do
      {:ok, inserted_model} ->
        {:ok, {inserted_model, wanted_fields}}
      {:error, changeset} ->
        {:error, form_module.get_popup_form(type: :create, action: :create, params: [], changeset: changeset)}
    end
  end

  defp get_changeset(module, params) do
    schema_module = module.__schema__
    changeset = schema_module.changeset(schema_module.__struct__, :create, params)
    {:ok, changeset}
  end
end
