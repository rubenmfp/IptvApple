cd "$RUNNER_TEMP"
curl -sL -o t.tar.xz https://download.videolan.org/cocoapods/prod/TVVLCKit-3.0-20260930-0854.tar.xz
mkdir t; tar xf t.tar.xz -C t

fw=$(find t -name "*.xcframework" -maxdepth 3 | head -1)
plutil -p $fw/Info.plist | grep -E "LibraryIdentifier|LibraryPath"

H=$fw/tvos-arm64/TVVLCKit.framework/Headers
echo "HEADERS $H"; ls $H
grep -nE "@property|^- \\(|^typedef|VLCMediaPlayerState[A-Z]|NS_SWIFT_NAME" $H/VLCMediaPlayer.h | head -170
grep -nE "@property|^- \(|^\+ \(" $H/VLCMedia.h | head -60
grep -nE "@property|^- \(|^\+ \(" $H/VLCTime.h | head -30
