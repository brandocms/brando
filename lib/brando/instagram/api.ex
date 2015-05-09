defmodule Brando.Instagram.API do
  @moduledoc """
  API functions for Instagram
  """
  use HTTPoison.Base
  alias HTTPoison.Response
  alias Brando.Instagram
  alias Brando.InstagramImage

  defp process_url(url), do:
    "https://api.instagram.com/v1/" <> url

  @doc """
  Main entry from genserver's `:poll`.
  Checks if we want `:user` or `:tags`
  """
  def fetch(filter) do
    case Instagram.cfg(:fetch) do
      {:user, username} ->
        if filter == :blank, do: filter = InstagramImage.get_last_created_time
        images_for_user(username, min_timestamp: filter)
        {:ok, InstagramImage.get_last_created_time}
      {:tags, tags} ->
        if filter == :blank, do: filter = InstagramImage.get_min_id
        images_for_tags(tags, min_id: filter)
        {:ok, InstagramImage.get_min_id}
    end
  end

  @doc """
  Get images for `username` by `min_timestamp`.
  """
  def images_for_user(username, min_timestamp: last_created_time) do
    {:ok, user_id} = get_user_id(username)
    case get!("users/#{user_id}/media/recent/?client_id=#{Instagram.cfg(:client_id)}&min_timestamp=#{last_created_time}") do
      %Response{body: body, status_code: 200} ->
        parse_images_for_user(body, username)
    end
    :ok
  end

  @doc """
  Get images for `username` by `max_id`.
  """
  def images_for_user(username, max_id: max_id) do
    {:ok, user_id} = get_user_id(username)
    case get!("users/#{user_id}/media/recent/?client_id=#{Instagram.cfg(:client_id)}&max_id=#{max_id}") do
      %Response{body: body, status_code: 200} ->
        parse_images_for_user(body, username)
    end
    :ok
  end

  @doc """
  Get images for `[tags]` by `min_timestamp`.
  """
  def images_for_tags(tags, min_id: min_id) do
    Enum.each tags, fn(tag) ->
      case get!("tags/#{tag}/media/recent?client_id=#{Instagram.cfg(:client_id)}&min_tag_id=#{min_id}") do
        %Response{body: body, status_code: 200} ->
          parse_images_for_tag(body)
      end
    end
    :ok
  end

  @doc """
  Store each image in `data` when we have tags. Ignore pagination (we
  could go on for years...)
  """
  def parse_images_for_tag([data: data, meta: _meta, pagination: _pagination]) do
    Enum.each data, fn(image) ->
      InstagramImage.store_image(image)
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
    case get! "users/search?q=#{username}&client_id=#{Instagram.cfg(:client_id)}" do
      %Response{body: [{:data, [%{"id" => id}]} | _]} -> {:ok, id}
      %Response{body: [data: [], meta: %{}]}          -> {:error, "Fant ikke bruker: #{username}"}
      %Response{body: {:error, error}}                -> {:error, "API feil fra Instagram: #{inspect(error)}"}
      %Response{body: [meta: meta], status_code: 400} -> {:error, "API feil 400 fra Instagram: #{inspect(meta["error_message"])}"}
      {:error, %HTTPoison.Error{reason: reason}}      -> {:error, "Nettfeil fra HTTPoison: #{inspect(reason)}"}
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