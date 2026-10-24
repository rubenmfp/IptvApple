which pod; pod --version
pod repo list
for p in MobileVLCKit TVVLCKit VLCKit; do
  echo "=== $p"
  pod spec cat $p 2>&1 | head -60
done
