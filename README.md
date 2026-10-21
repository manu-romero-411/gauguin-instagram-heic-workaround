# gauguin-instagram-heic-workaround

A tiny Magisk module that hides the Qualcomm hardware HEIC encoder
(`c2.qti.heic.encoder`) from Android's codec list, so apps stop crashing the
codec service when they try to save a photo.

Fixes **Instagram photo/story uploads failing silently** on a Xiaomi Mi 10T
Lite 5G (`gauguin`) running LineageOS 24 (Android 17).

## Symptom

- Posting a photo or a story in Instagram fails with a generic error and
  nothing is uploaded.
- Videos upload fine.
- Same device and same app worked on an older LineageOS build based on
  Android 13.

## Root cause

When Instagram saves a captured photo it picks HEIC, because the device
advertises an HEIC encoder. On this build that encoder crashes the vendor
Codec2 service as soon as it starts encoding:

```
CCodec    : allocate(c2.qti.heic.encoder)
QC2Comp   : Create: Allocated component[1] for name c2.qti.heic.encoder
CCodec    : Codec2 component "c2.qti.heic.encoder" died.
MediaCodec: Codec reported err 0xffffffe0/DEAD_OBJECT, actionCode 0, while in state 6/STARTED
EncoderBase: onError: android.media.MediaCodec$CodecException: Error 0xffffffe0
SavePhotoUtil: android.media.MediaCodec$CodecException: Error 0xffffffe0
```

Right after that, `qti.c2.store` restarts on its own. Photo saving fails, so
the upload fails.

Video encoding is not affected: `c2.qti.avc.encoder` and
`c2.qti.hevc.encoder` work, and the `c2.qti.*` video decoders fail to start
but Android falls back to the software decoders.

The exact reason the encoder dies is not confirmed. It is most likely a
mismatch between the old Qualcomm vendor blobs and the newer Android
framework. This is a ROM/vendor bug, not an Instagram or permissions problem.

> Note: you may see `Could not find android.hardware.graphics.allocator.IAllocator/default
> in the VINTF manifest` from `servicemanager` in the same log. It also shows
> up while the video encoders work fine, so it is not the cause.

## The fix

The module installs a copy of `/vendor/etc/media_codecs_c2.xml` (via Magisk's
systemless overlay) with the `c2.qti.heic.encoder` block removed. Android no
longer advertises the encoder, and apps fall back to another format (JPEG in
practice).

## Install

1. Create a folder with the two files below and zip them, with the files at
   the root of the zip (no parent folder):

   ```
   no-heic-encoder.zip
   ├── module.prop
   └── customize.sh
   ```

   ```sh
   zip -r ../no-heic-encoder.zip .
   adb push ../no-heic-encoder.zip /sdcard/Download/
   ```

2. In the Magisk app: **Modules → Install from storage**, pick the zip.
3. Reboot.

### `module.prop`

```
id=no-heic-encoder
name=Disable Qualcomm HEIC encoder
version=1.0
versionCode=1
author=manu
description=Hides c2.qti.heic.encoder so apps fall back to JPEG
```

### `customize.sh`

```sh
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
```

The patch is generated at install time from your own `/vendor`, so it follows
whatever your vendor partition contains.

## Verify

Before installing, find where the codec is declared:

```sh
adb shell "grep -rl 'c2.qti.heic.encoder' /vendor/etc /odm/etc /system/etc 2>/dev/null"
adb shell dumpsys media.player | grep -i heic
```

To check the patch is safe on your device, preview it on your PC (the diff
must only show the deleted lines of that one `<MediaCodec>` block):

```sh
adb pull /vendor/etc/media_codecs_c2.xml
sed '/<MediaCodec name="c2.qti.heic.encoder"/,/<\/MediaCodec>/d' media_codecs_c2.xml > patched.xml
diff media_codecs_c2.xml patched.xml
```

After installing and rebooting, `dumpsys` should no longer list the encoder:

```sh
adb shell dumpsys media.player | grep -i heic
```

Then try posting a photo.

## Uninstall

Remove the module in the Magisk app and reboot. Nothing on `/vendor` is
modified.

## Tested on

| Item    | Value                                   |
|---------|-----------------------------------------|
| Device  | Xiaomi Mi 10T Lite 5G (`gauguin`)       |
| ROM     | LineageOS 24.0 nightly 20261011         |
| Build   | `CP2A.260605.016`                       |
| Root    | Magisk                                  |
| App     | Instagram 453.0.0.0.60                  |

## Limitations

- Written for the file layout of this device. The block name and file
  (`media_codecs_c2.xml`) may differ on other devices or vendor versions.
- If the encoder is still listed after rebooting, another source (for
  example `video_system_specs.json` or another XML under `/vendor` or `/odm`)
  is registering it too.
- Apps that specifically need HEIC encoding will lose that option.
