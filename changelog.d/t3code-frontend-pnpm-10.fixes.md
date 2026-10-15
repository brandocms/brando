- **A newly generated application's Docker build no longer stops at the
  frontend stage**. The template's `assets_frontend` stage copied
  `assets/frontend/.yalc`, which nothing creates (Jupiter comes from npm and
  the folder is ignored), and Docker fails a `COPY` whose source is missing.
  An application that installs Jupiter from Yalc adds the line back; the
  template's comment shows it.
