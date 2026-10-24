for p in MobileVLCKit TVVLCKit VLCKit; do
  h=$(printf %s "$p" | md5)
  a=${h:0:1}; b=${h:1:1}; c=${h:2:1}
  echo "=== $p ($a/$b/$c)"
  line=$(curl -s "https://cdn.cocoapods.org/all_pods_versions_${a}_${b}_${c}.txt" | grep "^$p/")
  echo "$line" | tr '/' '\n' | tail -6 | tr '\n' ' '; echo
  for v in $(echo "$line" | tr '/' '\n' | tail -3); do
    echo "--- $v"
    curl -s "https://cdn.cocoapods.org/Specs/$a/$b/$c/$p/$v/$p.podspec.json" | python3 -c "import json,sys;d=json.load(sys.stdin);print(json.dumps({k:d.get(k) for k in ('version','source','platforms','vendored_frameworks','frameworks','libraries','ios','tvos','osx','dependencies','subspecs')})[:1500])"
  done
done
