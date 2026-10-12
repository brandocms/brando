- **A picture block without alt text is described by its caption again.**
  Before 0.55, a picture block with no alt text of its own rendered its
  caption (title and credits) as `alt`; 0.55 rendered `alt=""`, so pictures
  converted from Villain lost their only description. The caption's text is
  used again, now without its HTML (legacy captions often hold an `<h3>`),
  and alt text set on the block or the image still comes first.
