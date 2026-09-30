# building & publishing performstat

## local build (arm64, this machine)

```bash
cd PerformStat
./scripts/build.sh          # → PerformStat/build/PerformStat.app
open build/PerformStat.app
```

requires command line tools (`xcode-select --install`). no other dependencies.

## making a release by hand

```bash
# from the repo root
ditto -c -k --keepParent PerformStat/build/PerformStat.app PerformStat-vX.Y.Z-macos.zip
shasum -a 256 PerformStat-vX.Y.Z-macos.zip > SHA256SUMS.txt
```

then create a GitHub release for tag `vX.Y.Z` and upload both files
(see `.github/workflows/release.yml` — pushing a `v*` tag does all of this
automatically on GitHub's macOS runners, including a universal arm64+x86_64
build and a DMG).

## website

`PerformStatSITE/` is a single self-contained `index.html` (css + logo inlined).
deploy it anywhere static — GitHub Pages, Netlify, an S3 bucket. the download
buttons point at https://github.com/leniboi643/PerformStat
