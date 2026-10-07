#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bridge="$repo_root/bin/org-workflow-client"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"

for command_name in systemctl emacsclient; do
    cat > "$test_dir/bin/$command_name" <<'FAKE'
#!/usr/bin/env bash
printf '%s\034' "$(basename "$0")" >> "$ORG_WORKFLOW_TEST_LOG"
for argument in "$@"; do
    printf '%s\034' "$argument" >> "$ORG_WORKFLOW_TEST_LOG"
done
printf '\n' >> "$ORG_WORKFLOW_TEST_LOG"
FAKE
    chmod +x "$test_dir/bin/$command_name"
done

export ORG_WORKFLOW_TEST_LOG="$test_dir/calls"
export PATH="$test_dir/bin:$PATH"

"$bridge" visit
expected_visit=$'systemctl\034--user\034start\034emacs.service\034\nemacsclient\034--alternate-editor=false\034--no-wait\034--reuse-frame\034\nsystemctl\034--user\034start\034emacs.service\034\nemacsclient\034--alternate-editor=false\034--eval\034(org-workflow-dispatch-in-frame (quote visit))\034'
actual_visit=$(cat "$ORG_WORKFLOW_TEST_LOG")
if [[ "$actual_visit" != "$expected_visit" ]]; then
    printf 'visit call sequence mismatch\nexpected: %q\nactual:   %q\n' \
        "$expected_visit" "$actual_visit" >&2
    exit 1
fi

: > "$ORG_WORKFLOW_TEST_LOG"
"$bridge" select
if ! tr '\034' '\n' < "$ORG_WORKFLOW_TEST_LOG" | grep -Fxq '(org-workflow-select-in-new-frame)'; then
    printf 'select did not request a new selector frame\n' >&2
    exit 1
fi

: > "$ORG_WORKFLOW_TEST_LOG"
"$bridge" step
expected_step=$'systemctl\034--user\034start\034emacs.service\034\nemacsclient\034--alternate-editor=false\034--no-wait\034--reuse-frame\034\nsystemctl\034--user\034start\034emacs.service\034\nemacsclient\034--alternate-editor=false\034--eval\034(org-workflow-dispatch-in-frame (quote step))\034'
actual_step=$(cat "$ORG_WORKFLOW_TEST_LOG")
if [[ "$actual_step" != "$expected_step" ]]; then
    printf 'step call sequence mismatch\nexpected: %q\nactual:   %q\n' \
        "$expected_step" "$actual_step" >&2
    exit 1
fi

for action in agenda week; do
    : > "$ORG_WORKFLOW_TEST_LOG"
    "$bridge" "$action"
    expected=${expected_visit//quote visit/quote $action}
    [[ $(cat "$ORG_WORKFLOW_TEST_LOG") == "$expected" ]] || {
        printf '%s did not use the graphical-frame bridge\n' "$action" >&2
        exit 1
    }
done

: > "$ORG_WORKFLOW_TEST_LOG"
"$bridge" start
expected_start=$'systemctl\034--user\034start\034emacs.service\034\nemacsclient\034--alternate-editor=false\034--eval\034(org-workflow-dispatch (quote start))\034'
actual_start=$(cat "$ORG_WORKFLOW_TEST_LOG")
if [[ "$actual_start" != "$expected_start" ]]; then
    printf 'background call sequence mismatch\nexpected: %q\nactual:   %q\n' \
        "$expected_start" "$actual_start" >&2
    exit 1
fi

: > "$ORG_WORKFLOW_TEST_LOG"
"$bridge" toggle
expected_toggle=$'systemctl\034--user\034start\034emacs.service\034\nemacsclient\034--alternate-editor=false\034--eval\034(org-workflow-dispatch (quote toggle))\034'
actual_toggle=$(cat "$ORG_WORKFLOW_TEST_LOG")
if [[ "$actual_toggle" != "$expected_toggle" ]]; then
    printf 'toggle call sequence mismatch\nexpected: %q\nactual:   %q\n' \
        "$expected_toggle" "$actual_toggle" >&2
    exit 1
fi

: > "$ORG_WORKFLOW_TEST_LOG"
if "$bridge" erase-buffer >"$test_dir/stdout" 2>"$test_dir/stderr"; then
    printf 'unknown action unexpectedly succeeded\n' >&2
    exit 1
fi
if [[ -s "$ORG_WORKFLOW_TEST_LOG" ]]; then
    printf 'unknown action reached emacsclient\n' >&2
    exit 1
fi

printf 'org-workflow client bridge tests passed\n'
