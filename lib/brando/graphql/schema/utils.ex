defmodule Brando.Schema.Utils do
  @moduledoc """
  Helper utility functions for GraphQL resolvers
  """
  def resolve_avatar(%{avatar: nil}, _, _) do
    {:ok, "/images/admin/avatar.png"}
  end
  def resolve_avatar(user, %{type: type}, _) do
    img_url = Brando.Utils.img_url(user.avatar, type, prefix: Brando.Utils.media_url())
    {:ok, img_url}
  end

  def resolve_assignment_file(%{file: nil}, _, _) do
    {:ok, ""}
  end
  def resolve_assignment_file(assignment_file, %{type: _type}, _) do
    {:ok, assignment_file.file.file_name}
  end

  def resolve_company_file(%{file: nil}, _, _) do
    {:ok, ""}
  end
  def resolve_company_file(company_file, _, _) do
    {:ok, company_file.file.file_name}
  end
end
