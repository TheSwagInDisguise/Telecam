# Telecam

An iPhone camera app for shooting through a clip-on 2x tele add-on lens
(main or telephoto camera), with multi-frame RAW super-resolution processing
in the spirit of Adobe Project Indigo.

## Status

**Step B (in progress): capture app**
- Locks to one *physical* camera (Main or Telephoto), so iOS never switches
  lenses behind the add-on.
- Shoots bursts of 1–16 **Bayer RAW** DNGs with focus/exposure/white balance
  locked across the burst.
- Saves to `Documents/Bursts/<timestamp>_<lens>[_addon2x]/` with a
  `burst.json` (exposure, ISO, lens, etc.). No GPS is written.
  Open in the **Files** app: *On My iPhone → Telecam*.

**Next**
- Step A: prototype the super-resolution merge (Python) on real bursts.
- Add-on lens correction (vignetting, distortion, colour fringing).
- Step C: port the merge to Metal and run it on-device.

## Builds

Every push builds an unsigned `.ipa` with GitHub Actions
(`.github/workflows/build.yml`) and attaches it to a pre-release on the
Releases page. Install with Signulous, SideStore or AltStore.

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate`.
