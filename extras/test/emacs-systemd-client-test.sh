#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
client="$repo_root/bin/emacs-systemd-client"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"

for command_name in systemctl emacsclient; do
    cat > "$test_dir/bin/$command_name" <<'FAKE'
#!/usr/bin/env bash
printf '%s\034' "$(basename "$0")" >> "$EMACS_SYSTEMD_TEST_LOG"
for argument in "$@"; do
    printf '%s\034' "$argument" >> "$EMACS_SYSTEMD_TEST_LOG"
done
printf '\n' >> "$EMACS_SYSTEMD_TEST_LOG"
FAKE
    chmod +x "$test_dir/bin/$command_name"
done

export EMACS_SYSTEMD_TEST_LOG="$test_dir/calls"
export PATH="$test_dir/bin:$PATH"

"$client" --no-wait --create-frame
expected=$'systemctl\034--user\034start\034emacs.service\034\nemacsclient\034--alternate-editor=false\034--no-wait\034--create-frame\034'
actual=$(cat "$EMACS_SYSTEMD_TEST_LOG")
if [[ "$actual" != "$expected" ]]; then
    printf 'systemd client call sequence mismatch\nexpected: %q\nactual:   %q\n' \
        "$expected" "$actual" >&2
    exit 1
fi

printf 'emacs systemd client tests passed\n'
