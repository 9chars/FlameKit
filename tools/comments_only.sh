#!/bin/bash
# tools/comments_only.sh <git ref>: checks that every changed .lua/.cpp/.hpp/.h/.c file differs from <ref> in comments
# and blank lines only (owner 2026-11-22 13:15 "don't break any of the source code putting the comments in").
# Lua: the token streams without comments must be identical (tools/lua_tokens.py). C++: identical after gcc's
# preprocessor strips the comments (gcc -fpreprocessed), blank lines ignored. Prints "same code" or "CODE CHANGED" per
# file; exits 1 when any code changed. Run from the repository's top folder.
ref=${1:?usage: tools/comments_only.sh <git ref>}
here=$(cd "$(dirname "$0")" && pwd)
bad=0
for f in $(git diff --name-only "$ref" -- '*.lua' '*.cpp' '*.hpp' '*.h' '*.c'); do
  [ -f "$f" ] || { echo "GONE $f"; bad=1; continue; }
  old=$(mktemp)
  git show "$ref:$f" > "$old"
  case "$f" in
    *.lua) python3 "$here/lua_tokens.py" "$old" "$f" ;;
    *) a=$(gcc -fpreprocessed -dD -E -P -x c++ "$old" 2>/dev/null | grep -v '^[[:space:]]*$' | md5sum)
       b=$(gcc -fpreprocessed -dD -E -P -x c++ "$f" 2>/dev/null | grep -v '^[[:space:]]*$' | md5sum)
       [ "$a" = "$b" ] ;;
  esac && echo "same code: $f" || { echo "CODE CHANGED: $f"; bad=1; }
  rm -f "$old"
done
exit $bad
