defmodule Brando.Admin.ImageCategoryController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """
  use Brando.Web, :controller
  use Brando.Sequence, [:controller, [model: Brando.ImageSeries, filter: &Brando.ImageSeries.get_by_category_id/1]]
  import Brando.Plug.Section
  import Brando.HTML.Inspect, only: [model_name: 2]

  plug :put_section, "images"
  plug :scrub_params, "imagecategory" when action in [:create, :update]
  plug :action

  @doc false
  def new(conn, _params) do
    conn
    |> render(:new)
  end

  @doc false
  def create(conn, %{"imagecategory" => imagecategory}) do
    model = conn.private[:category_model]
    case model.create(imagecategory, Brando.HTML.current_user(conn)) do
      {:ok, _} ->
        conn
        |> put_flash(:notice, "Kategori opprettet.")
        |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:imagecategory, imagecategory)
        |> assign(:errors, errors)
        |> put_flash(:error, "Feil i skjema")
        |> render(:new)
    end
  end

  @doc false
  def edit(conn, %{"id" => id}) do
    model = conn.private[:category_model]
    if data = model.get(id: String.to_integer(id)) do
      conn
      |> assign(:image_category, data)
      |> assign(:id, id)
      |> render(:edit)
    else
      conn |> put_status(:not_found) |> render(:not_found)
    end
  end

  @doc false
  def update(conn, %{"imagecategory" => form_data, "id" => id}) do
    model = conn.private[:category_model]
    record = model.get(id: String.to_integer(id))
    case model.update(record, form_data) do
      {:ok, _updated_record} ->
        conn
        |> put_flash(:notice, "Kategori oppdatert.")
        |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:image_category, form_data)
        |> assign(:errors, errors)
        |> assign(:id, id)
        |> put_flash(:error, "Feil i skjema")
        |> render(:edit)
    end
  end

  @doc false
  def configure(conn, %{"id" => category_id}) do
    model = conn.private[:category_model]
    if data = model.get(id: String.to_integer(category_id)) do
      {:ok, cfg} = Brando.Type.ImageConfig.dump(data.cfg)
      data = Map.put(data, :cfg, cfg)
      conn
      |> assign(:image_category, data)
      |> assign(:id, category_id)
      |> render(:configure)
    else
      conn |> put_status(:not_found) |> render(:not_found)
    end
  end

  @doc false
  def configure_patch(conn, %{"imagecategoryconfig" => form_data, "id" => id}) do
    model = conn.private[:category_model]
    record = model.get(id: String.to_integer(id))
    case model.update(record, form_data) do
      {:ok, _updated_record} ->
        conn
        |> put_flash(:notice, "Kategori konfigurert.")
        |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
      {:error, errors} ->
        conn
        |> assign(:image_category, form_data)
        |> assign(:errors, errors)
        |> assign(:id, id)
        |> put_flash(:error, "Feil i skjema")
        |> render(:edit)
    end
  end

  @doc false
  def delete_confirm(conn, %{"id" => id}) do
    model = conn.private[:category_model]
    record = model.get!(id: id)
    conn
    |> assign(:record, record)
    |> render(:delete_confirm)
  end

  @doc false
  def delete(conn, %{"id" => id}) do
    model = conn.private[:category_model]
    record = model.get!(id: id)
    model.delete(record)
    conn
    |> put_flash(:notice, "#{model_name(record, :singular)} #{model.__repr__(record)} slettet.")
    |> redirect(to: router_module(conn).__helpers__.admin_image_path(conn, :index))
  end
end