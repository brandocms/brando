defmodule Brando.CDNTest do
  @moduledoc """
  What `Brando.CDN` puts into strings other systems keep.

  A raise message is not a private place: it reaches the Logger, Oban's
  `errors` column and any attached error reporter. `upload_image/4` builds one
  out of the S3 config, and `get_s3_config/2` with `as: :keyword_list` hands
  back `%S3Config{}` through `Map.from_struct/1` — so the credentials are plain
  values in that list unless something drops them.
  """
  use ExUnit.Case, async: true

  @s3_config %Brando.CDN.S3Config{
    access_key_id: "TESTKEY",
    secret_access_key: "TESTSECRET",
    scheme: "https://",
    host: "ams3.digitaloceanspaces.com",
    region: "ams3"
  }

  # `bucket: nil` with a populated `:s3` is the shape that reaches the raise:
  # `get_bucket_for_image_config/1` returns `nil` while `get_s3_config/2`
  # succeeds and returns the credentials.
  defp bucketless_cfg do
    %{cdn: %Brando.CDN.Config{enabled: true, bucket: nil, s3: @s3_config}}
  end

  describe "upload_image/4 raising on a missing bucket" do
    # MUTATION: drop the `Keyword.drop/2` in `upload_image/4`, restoring
    # `inspect(s3_config, pretty: true)`. Measured: the test reddens on the
    # **first** refutation — both values are back in the message verbatim, but
    # they share a test, so the second one never runs to report it.
    test "does not put S3 credentials in the message" do
      exception =
        assert_raise RuntimeError, fn ->
          Brando.CDN.upload_image("src/key.jpg", "dest/key.jpg", bucketless_cfg(), 1)
        end

      refute exception.message =~ "TESTKEY"
      refute exception.message =~ "TESTSECRET"
    end

    # The redaction is only worth having if the message still identifies the
    # config it is complaining about. Asserted separately from the refutations
    # above so that "redact everything" cannot pass this file.
    test "still names the config it could not find a bucket for" do
      exception =
        assert_raise RuntimeError, fn ->
          Brando.CDN.upload_image("src/key.jpg", "dest/key.jpg", bucketless_cfg(), 1)
        end

      message = exception.message

      assert message =~ "missing s3_bucket"
      assert message =~ "ams3.digitaloceanspaces.com"
      assert message =~ "ams3"
    end
  end

  describe "inspecting a config" do
    # MUTATION: remove `@derive {Inspect, except: …}` from
    # `Brando.CDN.S3Config`. Both refutations go red.
    #
    # This is a *separate* guard from the one above, not a second test of it:
    # by the time `upload_image/4` builds its message the struct is already a
    # keyword list, which no `Inspect` derivation covers. Neither fix implies
    # the other, so neither test stands in for the other.
    test "redacts the credentials on the struct" do
      inspected = inspect(@s3_config)

      refute inspected =~ "TESTKEY"
      refute inspected =~ "TESTSECRET"
      assert inspected =~ "ams3.digitaloceanspaces.com"
    end

    test "redacts them when the struct is nested in a CDN config" do
      inspected = inspect(%Brando.CDN.Config{enabled: true, bucket: "b", s3: @s3_config})

      refute inspected =~ "TESTKEY"
      refute inspected =~ "TESTSECRET"
    end

    # The gap the derivation does not close, pinned so it stays known rather
    # than being rediscovered as a surprise. `as: :keyword_list` is documented
    # to return raw values; callers that interpolate it must drop the
    # credentials themselves, which is what `upload_image/4` now does.
    test "does not redact the keyword list, which is why the raise drops them itself" do
      inspected =
        bucketless_cfg()
        |> Brando.CDN.get_s3_config(as: :keyword_list)
        |> inspect()

      assert inspected =~ "TESTKEY"
      assert inspected =~ "TESTSECRET"
    end
  end
end
