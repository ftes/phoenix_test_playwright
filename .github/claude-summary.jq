# Claude's final message and each denied call's command, path or URL, for the step summary.
# Nothing more: this repo is public, and the full transcript can contain secrets.
.[] | select(.type == "result")
  | (.result // .subtype),
    (.permission_denials // [] | select(length > 0) | "\n**Denied tool calls (\(length)):**\n",
      (.[] | (.tool_input | .command // .file_path // .path // .pattern // .url // "" | gsub("\\s+"; " ") | .[:200]) as $arg
        | "- \(.tool_name)" + (if $arg == "" then "" else ": `` \($arg) ``" end)))
