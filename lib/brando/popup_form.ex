defmodule Brando.PopupForm do
  @moduledoc """
  Helper functions for displaying popup forms from javascript through the system channel.

  ## Usage

  First, register the form in your app's endpoint startup. The first argument is the
  name of the schema, second is the form module and third is a list of fields you want
  returned if repo insertion is successful:

      Brando.PopupForm.Registry.register(:accounts, "client", MyApp.ClientForm, "Create client", [:id, :name])

  Then add javascript to your app:

      import {PopupForm, brando} from "brando";

      let params = [];
      let initialValues = {email: 'sample@email.com'};
      let clientForm = new PopupForm("accounts", brando.language, clientInsertionSuccess,
                                     params, initialValues);

      $('.avatar img').click((e) => {
          clientForm.show();
      });

      function clientInsertionSuccess(fields) {
          // here you'd insert the returned fields into a select or something similar.
          console.log(`${fields.id} --> ${fields.username}`);
      }

  That's it!

  No routing is neccessary, since PopupForms communicate through Brando's system channel.
  """

  alias Brando.PopupForm.Registry

  @doc """
  Returns Brando.Form struct for registered popup form `name`
  """
  @spec create(String.t, Keyword.t) :: Brando.Form.t | no_return
  def create(key, params \\ [], initial_values \\ %{}) do
    with {:ok, {_, form_module, _, _}} <- Registry.get(key),
         {:ok, changeset}              <- get_changeset(form_module, nil, initial_values),
      do: form_module.get_popup_form(
        type:      :create,
        action:    :create,
        params:    params,
        changeset: changeset
      )
  end

  @doc """
  Posts popup form `data` to registered `name`
  """
  @spec post(String.t, String.t, Phoenix.Socket.t) :: {:ok, {Ecto.Schema.t, [atom]}} |
                                                      {:error, Brando.Form.t}
  def post(key, data, socket) do
    {:ok, {name, mod, _, fields}} = Registry.get(key)
    params                        = data
                                    |> Plug.Conn.Query.decode
                                    |> Map.get(name)
                                    |> add_creator_to_params(socket)

    {:ok, changeset}              = get_changeset(mod, params)

    case Brando.repo.insert(changeset) do
      {:ok, inserted_model} ->
        {:ok, {inserted_model, fields}}
      {:error, changeset} ->
        {:error, mod.get_popup_form(type: :create, action: :create,
                                    params: [], changeset: changeset)}
    end
  end

  defp add_creator_to_params(params, %Phoenix.Socket{assigns: %{user_id: user_id}}) do
    Map.put(params, "creator_id", user_id)
  end

  defp add_creator_to_params(params, _) do
    params
  end

  @spec get_changeset(atom, %{binary => term} | %{atom => term}) :: {:ok, Ecto.Changeset.t}
  defp get_changeset(module, params, initial_values \\ %{}) do
    schema_module = module.__schema__

    struct =
      schema_module.__struct__
      |> Map.merge(Brando.Utils.to_atom_map(initial_values))

    changeset = schema_module.changeset(struct, :create, params || %{})

    {:ok, changeset}
  end
end
