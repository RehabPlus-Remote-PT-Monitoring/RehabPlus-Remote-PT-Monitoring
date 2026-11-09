# third_party

Patched copies of packages, wired in through `dependency_overrides` in
pubspec.yaml.

## google_mlkit_commons (0.11.1, patched)

Copied from pub.dev `google_mlkit_commons-0.11.1` (without `example/`,
`test/` and its `analysis_options.yaml`, which includes a file from the
upstream monorepo). Only one file differs from upstream:
`ios/Classes/MLKVisionImage+FlutterPlugin.m`.

Why: on iOS every camera frame goes through `pixelBufferToVisionImage`, and
upstream created a brand-new `CIContext` there for every frame. Setting up a
Core Image context is expensive (it builds a GPU render pipeline), so it
added a lot of time to every pose result and the skeleton trailed behind the
patient on iPhone. Upstream 1.0.1 (Swift) still does this.

What changed:
1. BGRA frames (what the iPhone camera stream gives us) are turned into a
   CGImage directly with a CGBitmapContext: one plain copy, no GPU round trip.
2. Any other pixel format still goes through Core Image, but with ONE shared
   context created once (colour management off).

Android code is untouched.

To update: copy the new upstream version over this folder, re-apply the two
changes above (search for "RehabPlus patch"), and bump the version in this
file. Remove the override once upstream reuses its context.
