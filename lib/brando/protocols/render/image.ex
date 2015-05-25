defimpl Brando.Render, for: Brando.Image do
  def r(data) do
    if data.image do
      ~s(<img src="#{data.image.sizes[:thumb]}" />)
    end
  end
end