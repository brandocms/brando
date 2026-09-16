# The generated CMS layout is intentionally minimal. Supply application-owned
# navigation so the smoke browser can exercise the installed menu JS and CSS.
path = "lib/igniter_smoke_web/cms/layouts.ex"
source = File.read!(path)
marker = "        {@inner_content}"
true = String.contains?(source, marker)

navigation = ~S"""
<header data-nav>
  <nav id="menu" aria-label="Menu">
    <div class="mobile-bg"></div>
    <section class="main">
      <ul>
        <li><a href="/">Home</a></li>
        <li><a href="/about">About</a></li>
      </ul>
    </section>
    <figure class="menu-button">
      <a href="#menu" class="hamburger noanim" aria-label="Menu" aria-controls="menu" aria-expanded="false">
        <i></i>
        <i></i>
        <i></i>
      </a>
    </figure>
  </nav>
</header>
"""

replacement = String.replace(navigation <> "{@inner_content}", ~r/^/m, "        ")
File.write!(path, String.replace(source, marker, replacement, global: false))
