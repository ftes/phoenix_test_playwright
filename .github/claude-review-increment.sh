#!/usr/bin/env bash
# Compares this PR with the version Claude last reviewed, so a rebase skips the review and a later
# push can be reviewed by its increment. The last review is the marker its summary comment ends
# with (claude-code-review.yml). Writes to $GITHUB_OUTPUT:
#   head, fork  the PR head and the commit it forks from, for this review's marker
#   mode        full (no usable earlier review), increment or skip (same changes as reviewed)
#   note        one line on why, also put in the step summary
# In increment mode, what changed since the last review is in tmp/claude-review/increment.diff.
# Env: GH_TOKEN, REPO, PR, HEAD_SHA, BASE_REF.
set -uo pipefail

finish() {
  { echo "mode=$1"; echo "note=$2"; } >> "$GITHUB_OUTPUT"
  echo "$2" >> "$GITHUB_STEP_SUMMARY"
  exit 0
}

fork=$(git merge-base "origin/$BASE_REF" "$HEAD_SHA")
{ echo "head=$HEAD_SHA"; echo "fork=$fork"; } >> "$GITHUB_OUTPUT"
[ -n "$fork" ] || finish full "No fork point from $BASE_REF; full review."

# Claude's comments only: anyone can comment, and a forged marker could skip a review.
marker=$(gh api --paginate "repos/$REPO/issues/$PR/comments" \
  --jq '.[] | select(.user.login == "claude[bot]") | .body' |
  grep -oE 'claude-review: [0-9a-f]{40} [0-9a-f]{40}' | tail -n 1)
[ -n "$marker" ] || finish full "No earlier review of this PR; full review."
read -r _ old_head old_fork <<< "$marker"

# A rebase leaves the reviewed commits on no branch, and the checkout keeps no credentials.
auth=$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')
git -c "http.extraHeader=Authorization: Basic $auth" fetch --quiet --no-tags origin "$old_head" "$old_fork" ||
  finish full "Couldn't fetch the reviewed commit ${old_head:0:12}; full review."

if [ "$(git diff "$old_fork" "$old_head" | git patch-id --stable)" = "$(git diff "$fork" "$HEAD_SHA" | git patch-id --stable)" ]; then
  finish skip "Same changes as the review of ${old_head:0:12} (a rebase, or no change); review skipped."
fi

# The reviewed changes replayed onto today's fork point, so a moved base's own changes don't show.
replayed=$(git merge-tree --write-tree --merge-base "$old_fork" "$fork" "$old_head") ||
  finish full "Rebasing the reviewed changes onto $BASE_REF conflicts; full review."
mkdir -p tmp/claude-review
git diff "$replayed" "$HEAD_SHA" > tmp/claude-review/increment.diff ||
  finish full "Couldn't diff with the review of ${old_head:0:12}; full review."
finish increment "Last reviewed at ${old_head:0:12}; tmp/claude-review/increment.diff has what changed since."
