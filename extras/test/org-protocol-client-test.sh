#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
client="$repo_root/bin/org-protocol-client"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"

for command_name in systemctl emacsclient; do
    fake_command="$test_dir/bin/$command_name"
    cp /dev/null "$fake_command"
    chmod +x "$fake_command"
    printf '%s\n' '#!/usr/bin/env bash' >> "$fake_command"
    printf '%s\n' 'printf '\''%s\034'\'' "$(basename "$0")" >> "$ORG_PROTOCOL_TEST_LOG"' >> "$fake_command"
    printf '%s\n' 'for argument in "$@"; do printf '\''%s\034'\'' "$argument" >> "$ORG_PROTOCOL_TEST_LOG"; done' >> "$fake_command"
    printf '%s\n' 'printf '\''\n'\'' >> "$ORG_PROTOCOL_TEST_LOG"' >> "$fake_command"
done

export ORG_PROTOCOL_TEST_LOG="$test_dir/calls"
export PATH="$test_dir/bin:$PATH"

url='org-protocol://capture?template=p&url=https%3A%2F%2Fexample.com'
"$client" "$url"

frame_parameters='((name . "capture") (width . 80) (height . 34))'
expected=$(printf 'systemctl\034--user\034start\034emacs.service\034\nemacsclient\034--alternate-editor=false\034--no-wait\034--create-frame\034--frame-parameters\034%s\034--\034%s\034\n' \
                  "$frame_parameters" "$url")
actual=$(cat "$ORG_PROTOCOL_TEST_LOG")
if [[ "$actual" != "$expected" ]]; then
    printf 'org-protocol client call sequence mismatch\nexpected: %q\nactual:   %q\n' \
        "$expected" "$actual" >&2
    exit 1
fi

if "$client" 'https://example.com' >/dev/null 2>&1; then
    printf 'org-protocol client accepted a non-protocol URL\n' >&2
    exit 1
fi

printf 'org-protocol client tests passed\n'
