# Test Files

The `sintel.*` files are taken from the Blender Open Movie Sintel.

They are licensed under the [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/) license.
Copyright © Blender Foundation | www.sintel.org

## ocr-samples.json

Twelve subtitle frames, each stored as its palette and its per-pixel palette indices, paired with the
text it should recognize as. `recognizesAntiAliasedFrames` feeds them through `SubtitleProcessor` and
compares the text alone, which is what makes it sensitive to changes in how images are prepared for
OCR. Six frames use a VobSub palette and six a PGS one, because the two are very different: VobSub has
four colors with a coarse alpha per color, PGS a full 256 color palette with 8 bit alpha.

Each frame is a row of unrelated words in random order, assembled from individual word bitmaps that
were segmented out of many different subtitles and recombined. Nothing in a frame is a phrase anyone
wrote: the words are ordinary lowercase vocabulary, filtered to exclude capitalized words, so no name,
speaker label or line of dialogue survives into the fixture.

Real glyphs are used rather than freshly rendered ones because rendered text does not reproduce the
failure. Text drawn with Core Text has generous enough counters that flattening the anti-aliasing
leaves it readable, and a fixture built that way failed on at most two frames of eight instead of six
of six. The same is true of the Sintel files, where flattening changes one frame in twenty six.
