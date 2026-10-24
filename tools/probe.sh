for p in MobileVLCKit TVVLCKit VLCKit; do
  h=$(printf %s "$p" | md5)
  a=${h:0:1}; b=${h:1:1}; c=${h:2:1}
  echo "=== $p"
  true
  for v in 3.7.4 4.0.0a25; do
    u="https://cdn.cocoapods.org/Specs/$a/$b/$c/$p/$v/$p.podspec.json"
    code=$(curl -sL -o spec.json -w "%{http_code}" "$u"); echo "$v -> $code"
    [ "$code" = 200 ] || continue
    echo "--- $v"; python3 -c "import json;d=json.load(open(\"spec.json\"));d.pop(\"authors\",None);d.pop(\"description\",None);print(json.dumps(d,indent=1)[:3000])"
  done
done
echo "=== tailles"
for u in $(python3 - <<'P'
import json,glob
P
); do :; done
