#!/usr/bin/env bash
# Smoke test mini-WAF SQLi en los 3 gateways C1.
# Espera: baseline=passthrough, istio/kong=403 con header x-waf-block.
set -u
ENC="%27%20OR%201%3D1%20--%20"

get_tok() {
  curl -sk --resolve "realistic.local:$1:127.0.0.1" \
    -X POST -H "Content-Type: application/json" \
    -d '{"username":"demo","password":"demo123"}' \
    "https://realistic.local:$1/auth/login" 2>/dev/null \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null
}

for tag in "baseline:443" "istio:30997" "kong:30443"; do
  name=${tag%:*}
  port=${tag##*:}
  if [[ "$port" == "443" ]]; then portshow=""; else portshow=":$port"; fi
  TOK=$(get_tok "$port")
  echo "=== $name (port $port, tok-len=${#TOK}) ==="

  c1=$(curl -sk --resolve "realistic.local:$port:127.0.0.1" \
       -o /dev/null -w "%{http_code}" \
       -H "Authorization: Bearer $TOK" \
       "https://realistic.local${portshow}/api/products")

  c2=$(curl -sk --resolve "realistic.local:$port:127.0.0.1" \
       -o /dev/null -w "%{http_code}" \
       "https://realistic.local${portshow}/api/products?search=${ENC}")

  hdr=$(curl -sk --resolve "realistic.local:$port:127.0.0.1" \
        -D - -o /dev/null \
        "https://realistic.local${portshow}/api/products?search=${ENC}" 2>/dev/null \
        | grep -i "x-waf-block" | tr -d '\r' | tr -d '\n')

  c3=$(curl -sk --resolve "realistic.local:$port:127.0.0.1" \
       -o /dev/null -w "%{http_code}" \
       -X POST -H "Content-Type: application/json" \
       -H "Authorization: Bearer $TOK" \
       -d '{"name":"hack UNION SELECT password FROM users--","price":1}' \
       "https://realistic.local${portshow}/api/products")

  echo "  CRUD-legit-GET=$c1   SQLi-query=$c2 [$hdr]   SQLi-body-POST=$c3"
done
