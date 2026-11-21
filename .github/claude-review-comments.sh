#!/usr/bin/env bash
# Writes this PR's comments, reviews and review comments by maintainers (author association OWNER,
# MEMBER or COLLABORATOR) and claude[bot] to tmp/claude-review/comments.md, for the review prompt
# (claude-code-review.yml). Env: GH_TOKEN, REPO, PR.
set -euo pipefail

by='select((.author_association | IN("OWNER", "MEMBER", "COLLABORATOR")) or (.user.type == "Bot" and .user.login == "claude[bot]"))'
out=tmp/claude-review/comments.md
mkdir -p tmp/claude-review
{
  echo "# Comments"
  echo
  gh api --paginate "repos/$REPO/issues/$PR/comments" \
    --jq ".[] | $by"' | "## \(.user.login), \(.created_at)\n\n\(.body)\n"'
  echo "# Reviews"
  echo
  gh api --paginate "repos/$REPO/pulls/$PR/reviews" \
    --jq ".[] | $by"' | select((.body // "") != "") | "## \(.user.login), \(.state), \(.submitted_at)\n\n\(.body)\n"'
  echo "# Review comments"
  echo
  gh api --paginate "repos/$REPO/pulls/$PR/comments" \
    --jq ".[] | $by"' | "## \(.user.login) on \(.path):\(.line // .original_line), \(.created_at)\n\n\(.body)\n"'
} > "$out.part"
mv "$out.part" "$out"
