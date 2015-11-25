defmodule Brando.Instagram.API do
  @moduledoc """
  API functions for Instagram
  """
  use HTTPoison.Base
  require Logger

  alias Brando.SystemChannel
  alias Brando.Instagram
  alias Brando.InstagramImage

  @http_lib Brando.Instagram.config(:api_http_lib)

  @doc """
  Main entry from genserver's `:poll`.
  Checks if we want `:user` or `:tags`
  """
  def fetch(filter, cfg) do
    check_for_failed_downloads()
    do_fetch(filter, cfg)
  end

  defp do_fetch(:blank, {:user, username}) do
    images_for_user(username, min_timestamp: 0)
    {:ok, InstagramImage.get_last_created_time}
  end

  defp do_fetch(filter, {:user, username}) do
    images_for_user(username, min_timestamp: filter)
    {:ok, InstagramImage.get_last_created_time}
  end

  defp do_fetch(:blank, {:tags, tags}) do
    images_for_tags(tags, min_id: 0)
    {:ok, InstagramImage.get_min_id}
  end

  defp do_fetch(filter, {:tags, tags}) do
    images_for_tags(tags, min_id: filter)
    {:ok, InstagramImage.get_min_id}
  end

  @doc """
  Get images for `username` by `min_timestamp`.
  """
  def images_for_user(username, min_timestamp: last_created_time) do
    case get_user_id(username) do
      {:ok, user_id} ->
        response = @http_lib.get(
          "https://api.instagram.com/v1/users/#{user_id}/media/recent/" <>
          "?client_id=#{Instagram.config(:client_id)}" <>
          "&min_timestamp=#{last_created_time}"
        )
        case response do
          {:ok, %{body: body, status_code: 200}} ->
            parse_images_for_user(body, username)
          {:error, %{reason: reason}} ->
            {:error, "Error from HTTPoison: #{inspect(reason)}"}
        end
      {:error, errors} ->
        Logger.error("Instagram/images_for_user: #{inspect(errors)}")
    end
    :ok
  end

  @doc """
  Get images for `username` by `max_id`.
  """
  def images_for_user(username, max_id: max_id) do
    {:ok, user_id} = get_user_id(username)
    response = @http_lib.get(
      "https://api.instagram.com/v1/users/" <>
      "#{user_id}/media/recent/?client_id=#{Instagram.config(:client_id)}" <>
      "&max_id=#{max_id}"
    )
    case response do
      {:ok, %{body: body, status_code: 200}} ->
        parse_images_for_user(body, username)
      {:error, %{reason: reason}} ->
        {:error, "Error from HTTPoison: #{inspect(reason)}"}
    end
    :ok
  end

  @doc """
  Get images for `[tags]` by `min_timestamp`.
  """
  def images_for_tags(tags, min_id: min_id) do
    Enum.each tags, fn(tag) ->
      response = @http_lib.get(
        "https://api.instagram.com/v1/tags/#{tag}/media/recent" <>
        "?client_id=#{Instagram.config(:client_id)}&min_tag_id=#{min_id}"
      )
      case response do
        {:ok, %{body: body, status_code: 200}} ->
          parse_images_for_tag(body)
        {:error, %{reason: reason}} ->
          {:error, "Error from HTTPoison: #{inspect(reason)}"}
      end
    end
    :ok
  end

  defp get_media(media_id) do
    response = @http_lib.get(
      "https://api.instagram.com/v1/media/" <>
      "#{media_id}?client_id=#{Instagram.config(:client_id)}")
    case response do
      {:ok, %{body: body, status_code: 200}} ->
        parse_media(body)
      {:error, %{reason: reason}} ->
        {:error, "Error from HTTPoison: #{inspect(reason)}"}
    end
  end

  @doc """
  Get Instagram's user ID for `username`
  """
  def get_user_id(username) do
    response = @http_lib.get(
      "https://api.instagram.com/v1/users/search?q=#{username}" <>
      "&client_id=#{Instagram.config(:client_id)}"
    )
    case response do
      {:ok, %{body: [{:data, [%{"id" => id}]} | _]}} ->
        {:ok, id}
      {:ok, %{body: [data: [], meta: %{}]}} ->
        {:error, "User not found: #{username}"}
      {:ok, %{body: {:error, error}}} ->
        {:error, "Instagram API error: #{inspect(error)}"}
      {:ok, %{body: [meta: %{"error_message" => _, "error_type" => "OAuthAccessTokenException"}], status_code: 400}} ->
        {:error, "Instagram access_token not valid. Refreshing..."}
      {:ok, %{body: [meta: %{"error_message" => error_message}], status_code: 400}} ->
        {:error, "Instagram API 400 error: #{inspect(error_message)}"}
      {:ok, %{body: [{:data, multiple} | _]}} ->
        ret = for user <- multiple do
          Map.get(user, "username") == username && Map.get(user, "id") || ""
        end
        {:ok, Enum.join(ret)}
      {:error, %{reason: reason}} ->
        {:error, "Error from HTTPoison: #{inspect(reason)}"}
    end
  end

  defp parse_media([data: data, meta: _meta]) do
    InstagramImage.store_image(data)
    :timer.sleep(Brando.Instagram.config(:sleep))
  end

  @doc """
  Store each image in `data` when we have tags. Ignore pagination (we
  could go on for years...)
  """
  def parse_images_for_tag([data: data, meta: _meta, pagination: _pagination]) do
    Enum.each data, fn(image) ->
      InstagramImage.store_image(image)
      # lets be nice and wait between each image stored.
      :timer.sleep(Brando.Instagram.config(:sleep))
    end
    SystemChannel.log(:info, "InstagramServer: Lagret #{Enum.count(data)} bilder")
  end

  @doc """
  Store each image in `data`. Checks `pagination` for more images.
  """
  def parse_images_for_user([data: data, meta: _meta, pagination: pagination], username) do
    Enum.each data, fn(image) ->
      InstagramImage.store_image(image)
      # lets be nice and wait 5 seconds between storing images
      :timer.sleep(Brando.Instagram.config(:sleep))
    end
    SystemChannel.log(:info, "InstagramServer: Lagret #{Enum.count(data)} bilder")
    if map_size(pagination) != 0 do
      :timer.sleep(Brando.Instagram.config(:sleep))
      images_for_user(username, max_id: Map.get(pagination, "next_max_id"))
    end
  end

  @doc """
  Poison's callback for processing the json into a map
  """
  def process_response_body(body) do
    case Poison.decode(body) do
      {:ok, result}   ->
        Enum.map(result, fn({k, v}) -> {String.to_atom(k), v} end)
      {:error, :invalid} ->
        body
      {:error, errors} ->
        {:error, errors}
    end
  end

  defp check_for_failed_downloads do
    for failed <- InstagramImage.get_failed_downloads() do
      get_media(failed.instagram_id)
    end
  end
end
