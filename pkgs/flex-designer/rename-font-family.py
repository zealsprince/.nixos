# Rewrite a font's family name records. Used to ship Noto Color Emoji under
# the "Segoe UI Emoji" family name that FlexDesigner hardcodes for its emoji
# rendering layer.
import sys

from fontTools.ttLib import TTFont

src, family, dst = sys.argv[1:4]
font = TTFont(src)
for rec in font["name"].names:
    if rec.nameID in (1, 4, 16):
        rec.string = family
    elif rec.nameID == 6:
        rec.string = family.replace(" ", "")
font.save(dst)
