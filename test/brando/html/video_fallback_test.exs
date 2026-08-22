defmodule Brando.HTML.VideoFallbackTest do
  @moduledoc """
  `Brando.HTML.Video.video/1` used to be a partial function over its `:video`
  assign: clauses for each provider record, for a binary src, and for `nil` —
  and nothing else. A miss raised FunctionClauseError out of
  `Brando.Villain.Tags.Video.render/2`, which in the admin runs inside live
  preview, so it took the entry form down mid-save with every unsaved change in
  it. Observed in production while saving a page whose preview rendered
  `{% video entry.listing_video %}`.

  Both shapes below are ordinary states, not authoring mistakes, which is why
  the fallback renders the same empty comment `nil` already got rather than an
  error string.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Videos.Video

  @empty "<!-- empty video component -->"

  test "an unloaded association renders empty instead of raising" do
    not_loaded = %Ecto.Association.NotLoaded{
      __field__: :listing_video,
      __owner__: __MODULE__,
      __cardinality__: :one
    }

    assert render_component(&Brando.HTML.Video.video/1, %{video: not_loaded, opts: []}) =~ @empty
  end

  test "a provider video that is not ready yet renders empty instead of raising" do
    # The window between upload and the provider's webhook: there is no playback
    # id to render, which is why the :mux/:bunny/:cloudflare clauses all require
    # `status: :ready`.
    for type <- [:mux, :bunny] do
      video = %Video{type: type, status: :processing, meta: %{}}

      assert render_component(&Brando.HTML.Video.video/1, %{video: video, opts: []}) =~ @empty,
             "a #{type} video still transcoding did not render empty"
    end
  end

  test "the fallback did not swallow the shapes that do render" do
    video = %Video{
      type: :mux,
      status: :ready,
      meta: %{"mux" => %{"playback_id" => "abc123"}}
    }

    html = render_component(&Brando.HTML.Video.video/1, %{video: video, opts: []})

    refute html =~ @empty
    assert html =~ "abc123"
  end
end
