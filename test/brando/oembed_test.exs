defmodule Brando.OEmbedTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support

  alias Brando.OEmbed

  setup do
    put_test_env(OEmbed, req_options: [plug: {Req.Test, OEmbed}])
    :ok
  end

  test "returns the provider's metadata" do
    Req.Test.stub(OEmbed, &Req.Test.json(&1, %{"title" => "A video"}))

    assert OEmbed.get("vimeo", "https://vimeo.com/76979871") == {:ok, %{"title" => "A video"}}
  end

  test "asks once and returns an error, instead of retrying or raising" do
    test_pid = self()

    for failure <- [&Plug.Conn.send_resp(&1, 503, ""), &Req.Test.transport_error(&1, :timeout)] do
      Req.Test.stub(OEmbed, fn conn ->
        send(test_pid, :request)
        failure.(conn)
      end)

      assert {:error, _} = OEmbed.get("youtube", "https://youtu.be/dQw4w9WgXcQ")
      assert_received :request
      refute_received :request
    end
  end

  test "has no provider for an uploaded file" do
    assert OEmbed.get("file", "/media/clip.mp4") == {:error, "no oEmbed target"}
  end
end
