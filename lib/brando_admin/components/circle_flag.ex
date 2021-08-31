defmodule BrandoAdmin.Components.CircleFlag do
  use Surface.Component

  prop language, :string, required: true

  def render(assigns) do
    ~F"""
    <div class="circle circle-flag">
      <!-- from https://hatscripts.github.io/circle-flags/ -->
      {#case @language}
        {#match :en}
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 512 512"><mask id="en_flag"><circle
              cx="256"
              cy="256"
              r="256"
              fill="#fff" /></mask><g mask="url(#en_flag)"><path
                fill="#eee"
                d="M0 0h47.4l76.4 21 65.4-21h33.4l34.2 16.6L289.4 0h33.4l70.4 22.8L464.8 0h15.8l12.2 7.3L512 0v47.3l-19.9 78 19.9 63.9v33.4l-16.4 30.6 16.4 36.2v33.4l-15.1 68.7 15.1 73.3v15.9l-7.8 10.9L512 512h-47.3l-71-17.5-70.9 17.5h-33.4l-30-19.7-36.8 19.7h-33.3l-63.7-20.2L47.3 512H31.4l-10.6-8L0 512v-47.3l22.8-79L0 322.9v-33.4l25.3-32L0 222.6v-33.4l22.2-64.6L0 47.2V31.4l8-7.8z" /><path
                  fill="#0052b4"
                  d="M47.4 0l141.8 142V0H47.4zm275.4 0v142l142-142h-142zM0 47.2v142h142L0 47.2zm512 .1L370.1 189.2H512V47.3zM0 322.8v141.9l141.9-141.9H0zm370 0l142 142v-142H370zM189.3 370l-142 142h142V370zm133.5.1V512h141.9L322.8 370.1z" /><path
                    fill="#d80027"
                    d="M222.6 0v222.6H0v66.8h222.6V512h66.8V289.4H512v-66.8H289.4V0h-66.8z" /><path
                      fill="#d80027"
                      d="M0 0v31.4l157.7 157.8h31.5L0 0zm480.6 0L322.8 157.7v31.5L512 0h-31.4zM189.2 322.8L0 512h31.4l157.8-157.7v-31.5zm133.6 0L511.9 512h.1v-31.3L354.3 322.8h-31.5z" /></g></svg>

        {#match :no}
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 512 512"><mask id="no_flag"><circle
              cx="256"
              cy="256"
              r="256"
              fill="#fff" /></mask><g mask="url(#no_flag)"><path
                fill="#d80027"
                d="M0 0h100.2l66.1 53.5L233.7 0H512v189.3L466.3 257l45.7 65.8V512H233.7l-68-50.7-65.5 50.7H0V322.8l51.4-68.5-51.4-65z" /><path
                  fill="#eee"
                  d="M100.2 0v189.3H0v33.4l24.6 33L0 289.5v33.4h100.2V512h33.4l30.6-26.3 36.1 26.3h33.4V322.8H512v-33.4l-24.6-33.7 24.6-33v-33.4H233.7V0h-33.4l-33.8 25.3L133.6 0z" /><path
                    fill="#0052b4"
                    d="M133.6 0v222.7H0v66.7h133.6V512h66.7V289.4H512v-66.7H200.3V0z" /></g></svg>
        {#match :sv}
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 512 512"><mask id="sv_flag"><circle
              cx="256"
              cy="256"
              r="256"
              fill="#fff" /></mask><g mask="url(#sv_flag)"><path
                fill="#0052b4"
                d="M0 0h133.6l35.3 16.7L200.3 0H512v222.6l-22.6 31.7 22.6 35.1V512H200.3l-32-19.8-34.7 19.8H0V289.4l22.1-33.3L0 222.6z" /><path
                  fill="#ffda44"
                  d="M133.6 0v222.6H0v66.8h133.6V512h66.7V289.4H512v-66.8H200.3V0z" /></g></svg>
        {#match language}
          {language}
      {/case}
    </div>
    """
  end
end
