set -x
cd "$RUNNER_TEMP"
curl -sL -o m.tar.xz https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.0-20260922-1512.tar.xz
curl -sL -o t.tar.xz https://download.videolan.org/cocoapods/prod/TVVLCKit-3.0-20260930-0854.tar.xz
ls -la *.tar.xz; shasum -a 256 *.tar.xz
mkdir m t; tar xf m.tar.xz -C m; tar xf t.tar.xz -C t
find m t -maxdepth 4 | head -60
du -sh m t
for x in m t; do
  fw=$(find $x -name "*.xcframework" -maxdepth 3 | head -1)
  echo "== $fw"; plutil -p $fw/Info.plist | head -60
  for b in $(find $fw -maxdepth 3 -name "*.framework"); do
    n=$(basename $b .framework); echo "-- $b"; file $b/$n; ls $b; ls $b/Modules 2>/dev/null && cat $b/Modules/module.modulemap
    lipo -info $b/$n; otool -l $b/$n 2>/dev/null | grep -A4 -m2 "LC_BUILD_VERSION\|LC_VERSION_MIN" | head -12
  done
done
