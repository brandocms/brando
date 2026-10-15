- **A newly generated application's Docker build no longer stops at the
  frontend stage**. The template's `assets_frontend` stage copied
  `assets/frontend/.yalc`, which nothing creates (Jupiter comes from npm and
  the folder is ignored), and Docker fails a `COPY` whose source is missing.
  The copy is now optional (`COPY assets/frontend/.yal[c] ./.yalc/`), so an
  application that installs Jupiter from Yalc still has it copied.
