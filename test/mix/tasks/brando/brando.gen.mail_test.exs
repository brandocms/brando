Code.require_file("../../../support/mix_helper.exs", __DIR__)

defmodule Mix.Tasks.Brando.Gen.MailTest do
  use ExUnit.Case
  import MixHelper

  setup do
    Mix.Task.clear()
    :ok
  end

  test "generates html resource" do
    in_tmp("brando.gen.mail", fn ->
      Mix.Tasks.Brando.Gen.Mail.run([])

      # test gallery
      assert_file("lib/brando/mailer.ex", fn file ->
        assert file ==
                 "defmodule Brando.Mailer do\n  use Swoosh.Mailer, otp_app: :brando\nend\n"
      end)

      assert_file("lib/brando/emails.ex", fn file ->
        assert file =~
                 "defmodule Brando.Emails do\n"
      end)
    end)
  end
end
