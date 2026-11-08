#!/usr/bin/env bash
# Blocks secrets and personal data from entering this public repository.
#
#   scripts/privacy-scan.sh --staged   scan what is about to be committed (used by the pre-commit hook)
#   scripts/privacy-scan.sh --all      scan every tracked file (run before the first push)
#
# A line that is a deliberate false positive can end with the marker: privacy-scan:allow
set -euo pipefail

mode="${1:---staged}"
cd "$(git rev-parse --show-toplevel)"

# File names that must never be committed.
blocked_names='(^|/)(\.env(\..*)?|\.envrc|.*\.(p8|p12|pem|key|cer|mobileprovision|keystore|sqlite|db|dump)|credentials(\..*)?|.*chatgpt.*\.json|.*secrets?(\..*)?)$'

# Content patterns: private keys, provider keys, OAuth tokens, JWTs, generic key assignments,
# email addresses, absolute home paths, and booking details.
content_patterns=(
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'sk-[A-Za-z0-9_-]{20,}'
  'fsq3[A-Za-z0-9+/=]{20,}'
  'oaiapp_[A-Za-z0-9_-]{6,}'
  '"(access|refresh|id)_token"[[:space:]]*:[[:space:]]*"[^"]{16,}"'
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.'
  '(api[_-]?key|secret|password|passwd|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{12,}'
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
  '/Users/[A-Za-z0-9._-]+/'
  '/home/[A-Za-z0-9._-]+/'
  '\b[Ss]eats? [0-9]+'
  '\b[Cc]oach [A-Z]\b'
  '\b(booking|ticket|confirmation) (ref|reference|number)\b'
)
# Allowed email-like strings (placeholders and examples).
allowed_emails='@(example\.(com|org|net)|users\.noreply\.github\.com)|noreply@'

failures=0
report() { printf 'privacy-scan: %s\n' "$1" >&2; failures=$((failures + 1)); }

if [[ "$mode" == "--staged" ]]; then
  files=$(git diff --cached --name-only --diff-filter=ACMR)
else
  files=$(git ls-files)
fi

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if [[ "$file" =~ $blocked_names ]]; then
    report "blocked file name: $file"
  fi
done <<< "$files"

if [[ "$mode" == "--staged" ]]; then
  # Only lines being added in this commit, with their file names.
  lines=$(git diff --cached -U0 --diff-filter=ACMR --no-color \
    | awk '/^\+\+\+ b\//{file=substr($0,7)} /^\+[^+]/{print file ": " substr($0,2)}')
else
  lines=$(git ls-files -z | xargs -0 rg --no-heading --line-number --with-filename '' 2>/dev/null || true)
fi

for pattern in "${content_patterns[@]}"; do
  matches=$(printf '%s\n' "$lines" | rg -e "$pattern" | rg -v 'privacy-scan:allow' || true)
  if [[ "$pattern" == *'@[A-Za-z0-9.-]+'* ]]; then
    matches=$(printf '%s\n' "$matches" | rg -v -e "$allowed_emails" || true)
  fi
  if [[ -n "$matches" ]]; then
    report "pattern '$pattern' matched:"
    printf '%s\n' "$matches" | head -5 | sed 's/^/    /' >&2
  fi
done

if (( failures > 0 )); then
  printf 'privacy-scan: %d problem(s). Fix them, or end a deliberate false positive line with privacy-scan:allow.\n' "$failures" >&2
  exit 1
fi
printf 'privacy-scan: clean (%s)\n' "$mode"
