defmodule BrandoAdmin.Components.Assets.VideoFromURL do
  @moduledoc """
  "Add from URL" for videos, shared by the video picker and the Videos
  library: the URL input, the video its address describes, the title lookup
  and the create.

  `input/1` renders the input with the `Brando.VideoURLParser` hook, which
  reads the address in the browser (YouTube, Vimeo, or a video file or HLS
  stream such as a Bunny or Mux stream URL) and pushes `url` with the
  provider, its id and the size it found. The owner's `handle_event("url", …)`
  hands that to `start/3`, which asks the provider's oEmbed endpoint for the
  title off the LiveView process: a slow provider would otherwise hold up the
  whole editor. The answer comes back to the owner's
  `handle_async(:url_video, …)`, which hands it to `finish/3` to create the
  video. `Brando.Videos.create_video/2` then queues the lookup of its
  thumbnail and duration (`Brando.Videos.Metadata`).

  The state is two of the owner's assigns: `:creating_video`, while the
  lookup runs, and `:url_video_ref`, the paste it answers. Clearing the ref
  (`cancel/1`) drops an answer still on its way.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  import Phoenix.LiveView, only: [start_async: 3]

  alias Phoenix.LiveView.JS

  require Logger

  @named_aspect_ratios [{16 / 9, "16:9"}, {4 / 3, "4:3"}, {21 / 9, "21:9"}, {1, "1:1"}, {9 / 16, "9:16"}]

  @doc "The owner's assigns, before the first paste."
  def assign_defaults(socket) do
    socket
    |> assign_new(:creating_video, fn -> false end)
    |> assign_new(:url_video_ref, fn -> nil end)
  end

  @doc """
  Looks the pasted video up and creates it once the provider has answered
  (`finish/3`). `params` are the hook's `url` event; `attrs` are stored on
  the video as well, such as its `config_target` and `folder_id`. An address
  the hook could not read is refused, and the editor told.
  """
  def start(socket, params, attrs \\ %{}) do
    case video_params(params) do
      {:ok, video_params} ->
        video_params = Map.merge(video_params, attrs)
        ref = make_ref()

        socket
        |> assign(:creating_video, true)
        |> assign(:url_video_ref, ref)
        |> start_async(
          :url_video,
          Brando.Tenant.capture_context(fn ->
            {ref, video_params, metadata(video_params.type, video_params.source_url)}
          end)
        )

      :error ->
        send(self(), {:toast, gettext("This address can't be used for a video.")})
        assign(socket, :creating_video, false)
    end
  end

  @doc "Drops a lookup still running: its answer creates nothing."
  def cancel(socket) do
    socket
    |> assign(:creating_video, false)
    |> assign(:url_video_ref, nil)
  end

  @doc """
  The lookup's answer, from the owner's `handle_async(:url_video, result,
  socket)`: creates the video as `user`.

    * `{:ok, video, socket}`: created.
    * `{:error, :forbidden, socket}`: `user` may not add videos. The owner
      says so.
    * `{:error, reason, socket}`: not created. An address that can't be used
      for a video has been reported to the editor already.
    * `{:ignore, socket}`: the answer is for a paste dropped since
      (`cancel/1`, or another paste).
  """
  def finish(socket, {:ok, {ref, video_params, {title, description, _thumbnail_url}}}, user) do
    case socket.assigns do
      %{url_video_ref: ^ref} -> create(socket, Map.merge(video_params, %{title: title, caption: description}), user)
      # A newer URL needs no check: LiveView drops a replaced task's reply.
      _ -> {:ignore, socket}
    end
  end

  def finish(socket, {:exit, reason}, _user) do
    Logger.warning("Video from URL failed: #{inspect(reason)}")
    {:error, :lookup_failed, assign(socket, :creating_video, false)}
  end

  defp create(socket, video_params, user) do
    result =
      with :ok <- Brando.Authorization.Media.authorize(user, :video),
           do: Brando.Videos.create_video(video_params, user)

    socket = assign(socket, :creating_video, false)

    case result do
      {:ok, video} ->
        {:ok, video, socket}

      {:error, message} when is_binary(message) ->
        {:error, :forbidden, socket}

      {:error, changeset} ->
        error_msg =
          Enum.map_join(changeset.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)

        Logger.warning("Video changeset error: #{error_msg}")

        if Keyword.has_key?(changeset.errors, :source_url) do
          send(self(), {:toast, gettext("This address can't be used for a video.")})
          {:error, :invalid_url, socket}
        else
          {:error, :invalid, socket}
        end
    end
  end

  @doc """
  The video the hook's `url` event describes: its type, address, the
  provider's id and its size. `:error` when the hook could not read the
  address: it then sends no provider or id (an address without a scheme,
  which the browser does not parse).
  """
  def video_params(%{"width" => width, "height" => height, "source" => source, "remoteId" => remote_id, "url" => url})
      when is_binary(source) and is_binary(remote_id) and is_binary(url) do
    video_type = video_type(source)

    {:ok,
     %{
       type: video_type,
       source_url: url,
       remote_id: remote_id(video_type, url, remote_id),
       width: width,
       height: height,
       aspect_ratio: aspect_ratio(width, height)
     }}
  end

  def video_params(_params), do: :error

  @doc "The video type for the hook's `source`."
  def video_type("vimeo"), do: :vimeo
  def video_type("youtube"), do: :youtube
  def video_type(_source), do: :external_file

  # The client parser hands back everything after `vimeo.com/` — including an
  # unlisted video's hash — so a Vimeo id is taken from the URL instead.
  defp remote_id(:vimeo, url, remote_id) do
    case Brando.Videos.VimeoURL.parse(url) do
      {:ok, %{id: id}} -> id
      :error -> remote_id
    end
  end

  defp remote_id(_video_type, _url, remote_id), do: remote_id

  @doc """
  `{title, description, thumbnail_url}` for the video at `url`: from the
  provider's oEmbed endpoint for YouTube and Vimeo, from the file name for
  anything else. A provider that doesn't answer gives a placeholder title.
  """
  def metadata(:youtube, url), do: oembed_metadata("youtube", url)
  def metadata(:vimeo, url), do: oembed_metadata("vimeo", url)
  def metadata(_video_type, url), do: {title_from_url(url), nil, nil}

  defp oembed_metadata(provider, url) do
    case Brando.OEmbed.get(provider, url) do
      {:ok, data} ->
        {
          Map.get(data, "title", "#{String.capitalize(provider)} Video"),
          Map.get(data, "description"),
          Map.get(data, "thumbnail_url")
        }

      {:error, _} ->
        {"#{String.capitalize(provider)} Video", nil, nil}
    end
  end

  @doc """
  A title from the address's file name: `…/my_clip-01.mp4` is "my clip 01",
  and an address with no file name "Video".
  """
  def title_from_url(url) do
    URI.parse(url).path
    |> Path.basename()
    |> Path.rootname()
    |> String.replace(~r/[_-]/, " ")
    |> String.trim()
    |> case do
      "" -> "Video"
      title -> title
    end
  end

  @doc """
  The named aspect ratio of `width × height` ("16:9"), else "width:height";
  "16:9" without a size.
  """
  def aspect_ratio(width, height) when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    ratio = width / height

    Enum.find_value(@named_aspect_ratios, "#{width}:#{height}", fn {named_ratio, label} ->
      if abs(ratio - named_ratio) < 0.01, do: label
    end)
  end

  def aspect_ratio(_, _), do: "16:9"

  attr :id, :string, required: true, doc: "the owner's id; the input is `\#{id}-source-url`"

  attr :target, :any,
    default: nil,
    doc: "the component the hook pushes `url` to; without one, the LiveView it is in"

  attr :creating, :boolean, required: true, doc: "while the provider is asked"

  @doc """
  The URL input. Without a `target` the hook pushes to the element itself,
  which reaches the LiveView only when no component encloses it.
  """
  def input(assigns) do
    ~H"""
    <div
      class="video-url-parser"
      phx-hook="Brando.VideoURLParser"
      data-target={@target || "#video-url-parser-#{@id}"}
      id={"video-url-parser-#{@id}"}
    >
      <div class="video-picker-url-field">
        <label for={"#{@id}-source-url"}>{gettext("Video URL")}</label>
        <input
          id={"#{@id}-source-url"}
          type="text"
          class="text"
          placeholder={gettext("Paste YouTube, Vimeo or direct video URL")}
          phx-mounted={JS.focus()}
        />
        <button type="button" class="btn">
          <%= if @creating do %>
            {gettext("Creating...")}
          <% else %>
            {gettext("Create video")}
          <% end %>
        </button>
        <%!-- The hook shows this while it reads the URL; from then on the
             server keeps it up until the provider has answered. --%>
        <div class={["video-picker-analyzing", !@creating && "hidden"]}>
          <div class="spinner"></div>
          <span>{gettext("Analyzing video...")}</span>
        </div>
      </div>
    </div>
    """
  end
end
