cd "$RUNNER_TEMP"
curl -sL -o t.tar.xz https://download.videolan.org/cocoapods/prod/TVVLCKit-3.0-20260930-0854.tar.xz
mkdir t; tar xf t.tar.xz -C t
find t -maxdepth 3 -not -path "*/doc/*" -not -path "*Sample*" | head -30
fw=$(find t -name "*.xcframework" -maxdepth 3 | head -1)
plutil -p $fw/Info.plist | grep -E "LibraryIdentifier|LibraryPath"
for b in $(find $fw -maxdepth 2 -name "*.framework"); do n=$(basename $b .framework); file $b/$n | head -3; ls $b; done
H=$(find $fw -path "*appletvos*" -o -path "*tvos-arm64*" | grep "Headers$" | head -1)
[ -z "$H" ] && H=$(find $fw -name Headers -type d | head -1)
echo "HEADERS $H"; ls $H
grep -nE "@property|^- \(|^typedef|VLCMediaPlayerState[A-Z]" $H/VLCMediaPlayer.h | head -150
grep -nE "@property|^- \(|^\+ \(" $H/VLCMedia.h | head -60
grep -nE "@property|^- \(|^\+ \(" $H/VLCTime.h | head -30
