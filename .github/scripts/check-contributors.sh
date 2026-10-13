#!/usr/bin/env bash
# Fails when a commit in <range> names an AI agent as its author, committer
# or co-author. See "Contributors" in CONTRIBUTING.md for the policy.
#
#   check-contributors.sh <base>..<head> [pr-author-login]
set -euo pipefail

range=${1:?usage: check-contributors.sh <base>..<head> [pr-author-login]}
pr_author=${2:-}

# Matched case-insensitively against identities and trailers only — never
# against subjects or code, where "Gemini" or "Copilot" is this package's
# subject matter rather than a contributor. Bare human names (Devin, Jules)
# are matched only in the forms the agents actually use.
agents='claude|anthropic|codex|openai|chatgpt|copilot|cursoragent|cursor\.com|cursor\[bot\]|devin-ai|devin\[bot\]|google-labs-jules|gemini-code-assist|sweep-ai|\baider\b|ai[- ]agent'

# Trailers that attribute a commit to someone. Claude-Session and friends are
# attribution by their very presence, whatever their value.
attribution_trailer='^(co-authored-by|signed-off-by|authored-by|assisted-by|generated-by|reviewed-by|helped-by)[[:space:]]*:'
agent_trailer='^(claude-session|codex-session|x-ai-agent)[[:space:]]*:'
generated_line='generated (with|by) \[?(claude|codex|chatgpt|copilot|cursor|devin|aider)'

failures=0
fail() {
  echo "::error::$1"
  failures=$((failures + 1))
}

if [[ -n "$pr_author" ]] && grep -qiP "$agents" <<<"$pr_author"; then
  fail "Pull request opened by '$pr_author', an AI agent account. AI agents cannot be contributors to this repository."
fi

while IFS= read -r sha; do
  short=${sha:0:7}
  identity=$(git show -s --format='%an <%ae>%n%cn <%ce>' "$sha")
  if grep -qiP "$agents" <<<"$identity"; then
    fail "Commit $short is authored or committed by an AI agent: $(tr '\n' ' ' <<<"$identity")"
  fi

  body=$(git show -s --format='%B' "$sha")
  while IFS= read -r line; do
    if grep -qiE "$agent_trailer" <<<"$line"; then
      fail "Commit $short carries an AI agent trailer: $line"
    elif grep -qiE "$attribution_trailer" <<<"$line" && grep -qiP "$agents" <<<"$line"; then
      fail "Commit $short credits an AI agent: $line"
    elif grep -qiE "$generated_line" <<<"$line"; then
      fail "Commit $short is marked as AI-generated: $line"
    fi
  done <<<"$body"
done < <(git rev-list "$range")

if (( failures > 0 )); then
  echo "AI agents (Claude, Codex, Copilot and the like) cannot be authors," \
       "committers or co-authors here. Reword the commits so that a human" \
       "is the only contributor — see CONTRIBUTING.md#contributors."
  exit 1
fi
echo "All commits in $range have human contributors only."
