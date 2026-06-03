# test/redact.bats
load helpers
redact() { bash -c 'source "$1"; redact' _ "$PLUGIN_DIR/lib/redact.sh"; }

@test "redact: openai/anthropic sk- key" {
  run bash -c 'echo "key sk-abcdefghijklmnopqrstuvwx123" | { source "'"$PLUGIN_DIR"'/lib/redact.sh"; redact; }'
  [[ "$output" == *"sk-[REDACTED]"* ]]
  [[ "$output" != *"abcdefghij"* ]]
}

@test "redact: aws access key" {
  run bash -c 'echo "AKIAIOSFODNN7EXAMPLE" | { source "'"$PLUGIN_DIR"'/lib/redact.sh"; redact; }'
  [[ "$output" == *"[REDACTED]"* ]]
  [[ "$output" != *"AKIAIOSFODNN7EXAMPLE"* ]]
}

@test "redact: jwt" {
  run bash -c 'echo "tok eyJhbGciOi.eyJzdWIiOi.sIgnAtUr3xx" | { source "'"$PLUGIN_DIR"'/lib/redact.sh"; redact; }'
  [[ "$output" == *"[REDACTED]"* ]]
}

@test "redact: pem private key block" {
  run bash -c 'printf -- "-----BEGIN RSA PRIVATE KEY-----\nMIIabc\n-----END RSA PRIVATE KEY-----\n" | { source "'"$PLUGIN_DIR"'/lib/redact.sh"; redact; }'
  [[ "$output" == *"[REDACTED PRIVATE KEY]"* ]]
  [[ "$output" != *"MIIabc"* ]]
}

@test "redact: lowercase assignment" {
  run bash -c 'echo "api_key=supersecretvalue123" | { source "'"$PLUGIN_DIR"'/lib/redact.sh"; redact; }'
  [[ "$output" == *"api_key=[REDACTED]"* ]]
}

@test "redact: short uppercase env assignments" {
  run bash -c 'printf "API_TOKEN=abc123\nDB_PASSWORD=hunter2\nGH_TOKEN=ghxyz\n" | { source "'"$PLUGIN_DIR"'/lib/redact.sh"; redact; }'
  [[ "$output" == *"API_TOKEN=[REDACTED]"* ]]
  [[ "$output" == *"DB_PASSWORD=[REDACTED]"* ]]
  [[ "$output" == *"GH_TOKEN=[REDACTED]"* ]]
  [[ "$output" != *"hunter2"* ]]
}

@test "redact: leaves ordinary text alone" {
  run bash -c 'echo "the build is green" | { source "'"$PLUGIN_DIR"'/lib/redact.sh"; redact; }'
  [ "$output" = "the build is green" ]
}
