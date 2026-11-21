#!/usr/bin/env bash
# Writes this PR's comments, reviews and review comments by maintainers (author association OWNER,
# MEMBER or COLLABORATOR) and claude[bot] to tmp/claude-review/comments.md, for the review prompt
# (claude-code-review.yml). Env: GH_TOKEN, REPO, PR.
# shellcheck disable=SC2016 # $ in single quotes is GraphQL or jq, not shell.
set -euo pipefail

# The REST API doesn't say which review threads are resolved; GraphQL does.
resolved=$(gh api graphql --paginate -f owner="${REPO%/*}" -f name="${REPO#*/}" -F pr="$PR" -f query='
  query($owner: String!, $name: String!, $pr: Int!, $endCursor: String) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100, after: $endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes { isResolved comments(first: 100) { nodes { databaseId } } }
        }
      }
    }
  }' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved) | .comments.nodes[].databaseId' |
  paste -sd, -)
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
    --jq "[$resolved] as \$resolved | .[] | $by"' | "## \(.user.login) on \(.path):\(.line // .original_line), \(.created_at)\(if .id | IN($resolved[]) then " (thread resolved)" else "" end)\n\n\(.body)\n"'
} > "$out.part"
mv "$out.part" "$out"
