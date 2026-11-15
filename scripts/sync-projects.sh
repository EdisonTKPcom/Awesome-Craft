#!/bin/bash
# Refreshes projects/ snapshots: for each repo in repos.tsv, sparse-clones Awesome-Craft, re-vendors one project at its latest default-branch commit, pushes, and cleans up. Files over 95 MB and files with Slack webhook URLs are skipped and noted in SOURCES.md.
set -u; cd ~ || exit 1
unset GITHUB_TOKEN; export GIT_TERMINAL_PROMPT=0
LIST=${1:-"$(cd "$(dirname "$0")" && pwd)/repos.tsv"}
G="git -c user.name=EdisonTKP -c user.email=26972943+EdisonTKPcom@users.noreply.github.com"
push(){ git -c credential.helper= -c credential.helper='!gh auth git-credential' push origin main 2>&1 | tail -25; }
freekb(){ df -k ~ | awk 'NR==2{print $4}'; }
LOG=${LOG:-/tmp/sync-projects.log}; : > $LOG
W=~/ac-work; TMP=~/ac-tmp
while IFS=$'\t' read -r r lic; do
  name=$(basename "$r" | tr 'A-Z' 'a-z'); echo "== $r free=$(( $(freekb)/1024 ))MB" >>$LOG
  cd ~; rm -rf "$W" "$TMP"
  need=$(gh api "repos/$r" --jq .size 2>/dev/null || echo 0)
  if [ $(( $(freekb) - need*0 )) -lt 1500000 ]; then echo "SKIP low disk $r (repo ${need}KB)" >>$LOG; echo "$r	$lic" >> ~/repos-skipped.tsv; continue; fi
  git clone -q --filter=blob:none --no-checkout --depth 1 https://github.com/EdisonTKPcom/Awesome-Craft.git "$W" 2>>$LOG || { echo "CLONE SELF FAIL" >>$LOG; break; }
  (cd "$W" && git sparse-checkout set --no-cone '/*' '!/projects/*/' && git checkout -q main) 2>>$LOG
  if ! git clone -q --depth 1 "https://github.com/$r.git" "$TMP" 2>>$LOG; then echo "CLONE FAIL $r" >>$LOG; echo "$r	$lic" >> ~/repos-skipped.tsv; continue; fi
  if [ $(freekb) -lt 1000000 ]; then echo "SKIP disk after clone $r" >>$LOG; echo "$r	$lic" >> ~/repos-skipped.tsv; rm -rf "$TMP"; continue; fi
  sha=$(git -C "$TMP" rev-parse HEAD); rm -rf "$TMP/.git"
  [ -d "$TMP/.github/workflows" ] && mv "$TMP/.github/workflows" "$TMP/.github/workflows-upstream"
  big=$(cd "$TMP" && find . -type f -size +95M | sed 's#^\./##' | tr '\n' ' '); (cd "$TMP" && find . -type f -size +95M -delete)
  find "$TMP" -name .gitmodules -delete
  sec=$(grep -rlE 'hooks\.slack\.com/(services|workflows)/T[A-Z0-9]+' "$TMP" 2>/dev/null | sed "s|^$TMP/||" | tr '\n' ' ')
  for f in $sec; do rm -f "$TMP/$f"; done
  [ -n "$sec" ] && big="${big:-} secret-scan-removed: $sec"; echo "secret files: $sec" >>$LOG
  mv "$TMP" "$W/projects/$name"
  echo "| $name | https://github.com/$r | \`${sha:0:12}\` | $(date +%F) | $lic | ${big:-none} |" >> "$W/projects/SOURCES.md"
  (cd "$W" && $G add --sparse -f "projects/$name" projects/SOURCES.md >/dev/null 2>&1 && $G commit -qm "Vendor $r @ ${sha:0:12}" && push >>$LOG)
  echo "pushed $r $(git -C "$W" rev-parse --short HEAD)" >>$LOG
done < $LIST
rm -rf "$W" "$TMP"; echo DONE >>$LOG
