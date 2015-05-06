defmodule Brando.Instagram.API do
  @moduledoc """
  API functions for Instagram
  """
  use HTTPoison.Base
  alias HTTPoison.Response
  alias Brando.InstagramImage

  @cfg Application.get_env(:brando, Brando.Instagram)

  def process_url(url), do:
    "https://api.instagram.com/v1/" <> url

  @doc """
  Main entry from genserver's `:poll`.
  Checks if we want `:user` or `:tags`
  """
  def fetch(last_created_time) do
    case @cfg[:fetch] do
      {:user, username} ->
        images_for_user(username, min_timestamp: last_created_time)
        {:ok, InstagramImage.get_last_created_time}
      {:tags, tags} -> nil
    end
  end

  @doc """
  Get images for `username` by `min_timestamp`.
  """
  def images_for_user(username, min_timestamp: last_created_time) do
    {:ok, user_id} = get_user_id(username)
    case get!("users/#{user_id}/media/recent/?client_id=#{@cfg[:client_id]}&min_timestamp=#{last_created_time}") do
      %Response{body: body, status_code: 200} ->
        parse_images_for_user(body, username)
    end
  end

  @doc """
  Get images for `username`, with `max_id`. Called from pagination
  """
  def images_for_user(username, max_id: max_id) do
    {:ok, user_id} = get_user_id(username)
    case get!("users/#{user_id}/media/recent/?client_id=#{@cfg[:client_id]}&max_id=#{max_id}") do
      %Response{body: body, status_code: 200} ->
        parse_images_for_user(body, username)
    end
  end

  @doc """
  Store each image in `data`. Checks `pagination` for more images.
  """
  def parse_images_for_user([data: data, meta: _meta, pagination: pagination], username) do
    Enum.each data, fn(image) ->
      InstagramImage.store_image(image)
    end
    if map_size(pagination) != 0 do
      images_for_user(username, max_id: Map.get(pagination, "next_max_id"))
    end
  end

  @doc """
  Get Instagram's user ID for `username`
  """
  def get_user_id(username) do
    case get! "users/search?q=#{username}&client_id=#{@cfg[:client_id]}" do
      %Response{body: [{:data, [%{"id" => id}]} | _]} -> {:ok, id}
      %Response{body: [data: [], meta: %{}]} -> {:error, "Fant ikke bruker: #{username}"}
      %Response{body: {:error, error}} -> {:error, "API feil fra Instagram: #{inspect(error)}"}
    end
  end

  @doc """
  Poison's callback for processing the json into an elixir map
  """
  def process_response_body(body) do
    case body |> Poison.decode do
      {:ok, result} ->
        result
        |> Enum.map(fn({k, v}) -> {String.to_atom(k), v} end)
      {:error, error} ->
        {:error, error}
    end
  end
end