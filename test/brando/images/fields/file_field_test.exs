defmodule Brando.Files.Field.FileFieldTest do
  use ExUnit.Case, async: true
  import Brando.Files.Utils

  defmodule TestSchema do
    use Brando.Field.FileField

    @cfg %{
      allowed_mimetypes: ["application/pdf"],
      random_filename: true,
      upload_path: Path.join("pdfs", "reports"),
      size_limit: 10240000,
    }


    has_file_field :file, @cfg

    def cfg, do: struct!(Brando.Type.FileConfig, @cfg)
  end

  test "use works" do
    assert Brando.Files.Field.FileFieldTest.TestSchema.get_file_cfg(:file) == TestSchema.cfg
  end
end
