defmodule E2eProject.Projects do
  @moduledoc """
  Context for Client
  """

  # ++types
  @type id :: integer | binary
  @type params :: map
  @type user :: Brando.Users.User.t()
  @type client :: E2eProject.Projects.Client.t()
  @type category :: E2eProject.Projects.Category.t()
  @type project :: E2eProject.Projects.Project.t()
  # __types

  use Brando.Query
  import Ecto.Query

  # ++header
  alias E2eProject.Projects.Client
  alias E2eProject.Projects.Category
  alias E2eProject.Projects.Project
  # __header

  # ++code
  #
  # Client
  
  mutation :create, Client
  mutation :update, Client
  mutation :delete, Client
  
  query :list, Client do
    fn query -> from t in query end
  end
  
  filters Client do
    fn
      {:status, status}, query ->
        from q in query, where: ilike(q.status, ^"%#{status}%")
  
      {:language, language}, query ->
        from q in query, where: q.language == ^language
    end
  end
  
  query :single, Client, do: fn query -> from t in query end
  
  matches Client do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id
  
      {:status, status}, query ->
        from t in query, where: t.status == ^status
  
      {:slug, slug}, query ->
        from t in query, where: t.slug == ^slug
    end
  end
  
  #
  # Category
  
  mutation :create, Category
  mutation :update, Category
  mutation :delete, Category
  
  query :list, Category do
    fn query -> from t in query end
  end
  
  filters Category do
    fn
      {:status, status}, query ->
        from q in query, where: ilike(q.status, ^"%#{status}%")
  
      {:language, language}, query ->
        from q in query, where: q.language == ^language
    end
  end
  
  query :single, Category, do: fn query -> from t in query end
  
  matches Category do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id
  
      {:status, status}, query ->
        from t in query, where: t.status == ^status
  
      {:slug, slug}, query ->
        from t in query, where: t.slug == ^slug
    end
  end
  
  #
  # Project
  
  mutation :create, Project
  mutation :update, Project
  mutation :delete, Project
  
  query :list, Project do
    fn query -> from t in query end
  end
  
  filters Project do
    fn
      {:publish_at, publish_at}, query ->
        from q in query, where: ilike(q.publish_at, ^"%#{publish_at}%")
  
      {:language, language}, query ->
        from q in query, where: q.language == ^language
    end
  end
  
  query :single, Project, do: fn query -> from t in query end
  
  matches Project do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id
  
      {:publish_at, publish_at}, query ->
        from t in query, where: t.publish_at == ^publish_at
  
      {:slug, slug}, query ->
        from t in query, where: t.slug == ^slug
    end
  end
  
  # __code
end
