#!/usr/bin/env awk -f
#
# NOT A CODE PATH. This is documentation of where the original LOC figures came from,
# kept so a future reader can see what the tool replaced and why (TASK §11).
#
# `contrib loc` uses cloc, which is the classifier. This awk heuristic treats any
# trimmed line starting with /*, *, */ or // as a comment, which is wrong in exactly
# one interesting way: the two `*p_min = …;` dereferences in ssl_sock_darwin.c get
# filed as comments. That is why the darwin-tls branch reads +30/+32 here and +32/+30
# under cloc — and why the fixture set keeps both figures side by side.
#
# Any figure that leaves the workspace comes from cloc, never from this.
#
#   git diff --unified=0 "$BASE" "$BRANCH" -- '*.c' '*.h' '*.m' | awk -f loc-heuristic.awk
#
/^\+\+\+/ || /^---/ { next }
/^[+-]/ {
  sign = substr($0, 1, 1)
  t = substr($0, 2); gsub(/^[ \t]+|[ \t]+$/, "", t)

  if (t == "")                                      k = "blank"
  else if (t ~ /^\/\*/ || t ~ /^\*/ || t ~ /^\/\//) k = "comment"
  else                                              k = "code"
  if (sign == "+") add[k]++; else del[k]++

  # Reports its own ambiguity, never reclassifies. Over-inclusive on purpose.
  if (t ~ /^\*/ && t !~ /^\*\// && (t ~ /=/ || t ~ /;$/)) amb++
}
END {
  printf "code +%d -%d net %+d | comment +%d -%d net %+d | blank +%d -%d net %+d\n",
    add["code"],    del["code"],    add["code"]    - del["code"],
    add["comment"], del["comment"], add["comment"] - del["comment"],
    add["blank"],   del["blank"],   add["blank"]   - del["blank"]
  printf "warning: %d line(s) start with '*' and may be code, not comment — verify with cloc\n",
    amb + 0
}
