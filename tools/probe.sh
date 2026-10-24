for p in MobileVLCKit TVVLCKit VLCKit; do
  h=$(printf %s "$p" | md5)
  a=${h:0:1}; b=${h:1:1}; c=${h:2:1}
  echo "=== $p"
  curl -s "https://cdn.cocoapods.org/all_pods_versions_${a}_${b}_${c}.txt" | grep "^$p/"
  for v in 3.7.4 3.6.0 4.0.0a9 4.0.0a2; do
    u="https://cdn.cocoapods.org/Specs/$a/$b/$c/$p/$v/$p.podspec.json"
    code=$(curl -s -o spec.json -w "%{http_code}" "$u")
    [ "$code" = 200 ] || continue
    echo "--- $v"; head -c 2500 spec.json; echo
  done
done
