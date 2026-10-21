# Remove only the HEIC encoder block from the vendor codec list.
SRC=/vendor/etc/media_codecs_c2.xml
DEST="$MODPATH/system$SRC"

mkdir -p "$(dirname "$DEST")"
sed '/<MediaCodec name="c2.qti.heic.encoder"/,/<\/MediaCodec>/d' "$SRC" > "$DEST"

# Abort if nothing was removed, so a no-op module is not left installed.
if cmp -s "$SRC" "$DEST"; then
  abort "! HEIC block not found, nothing patched"
fi
ui_print "- Patched $SRC"
