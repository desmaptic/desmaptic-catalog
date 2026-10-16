# Bug in Linear › the issue, through Linear's GraphQL API, after report.zsh (item.json):
#   "team=\"\"   # ← …\nfolder=\"\"   # ← …\n@file:report.zsh\n@file:linear.zsh"
# The settings: team — the key of the Linear team that gets the issue ("ENG"), empty when the workspace has one
# team; folder — the project whose branch and last commit go with it, empty for none. Linear's personal API key is
# not a setting (the button travels through iCloud): it is kept in this Mac's Keychain, under the name
# desmaptic-linear, saved once in Terminal with `security add-generic-password -s desmaptic-linear -a linear -w`
# (macOS asks for the key without showing it). Without it the button refuses and says so.
# The key goes to curl through a descriptor, never the command line; every JSON is built by jq --arg.

key=$(security find-generic-password -s desmaptic-linear -w 2>/dev/null)
[[ -n $key ]] || fail config "No Linear key on this Mac: make a personal API key in Linear (Settings › Security & access), then save it in Terminal with security add-generic-password -s desmaptic-linear -a linear -w"
[[ -n $folder ]] && expand_folder

# linear <json>: asks Linear; the answer is in $tmp/answer. A refusal (no network, a refused key, an error Linear
# names) ends the tap with Linear's own words.
linear() {
  local code
  code=$(curl -q -s -m 15 -o "$tmp/answer" -w '%{http_code}' https://api.linear.app/graphql -H @/dev/fd/3 \
    -H "Content-Type: application/json" --data-binary @- 3<<< "Authorization: $key" <<< "$1")
  local why=$(jq -r '.errors[0].message // empty' "$tmp/answer" 2>/dev/null)
  local what=$(jq -r '.errors[0].extensions.code // empty' "$tmp/answer" 2>/dev/null)
  [[ $code == 000 ]] && fail network "Linear cannot be reached"
  [[ $code == 401 || $what == AUTHENTICATION_ERROR ]] && fail auth "Linear refused the key${why:+: $why}"
  [[ $code == 200 && -z $why ]] || fail other "Linear answered $code${why:+: $why}"
}

read_report
call update-button "{\"cellId\":\"$cell\",\"icon\":\"hourglass\"}" >/dev/null

# ---- the team ----
linear '{"query": "{ teams { nodes { id key } } }"}'
teams=$(jq -r '[.data.teams.nodes[].key] | join(", ")' "$tmp/answer")
if [[ -n $team ]]; then
  team_id=$(jq -r --arg k "$team" 'first(.data.teams.nodes[] | select((.key | ascii_upcase) == ($k | ascii_upcase)) | .id) // empty' "$tmp/answer")
  [[ -n $team_id ]] || fail config "No Linear team with the key $team; yours: $teams"
else
  (( $(jq '.data.teams.nodes | length' "$tmp/answer") == 1 )) ||
    fail config "Set the team in this button’s settings, one of: $teams"
  team_id=$(jq -r '.data.teams.nodes[0].id' "$tmp/answer")
fi

# ---- what the Mac adds ----
context
if [[ -n $shot ]]; then
  # Linear keeps files at an address it signs for one upload: ask for it, put the PNG there, link it.
  size=$(zstat +size -- "$shot")
  linear "$(jq -nc --argjson s $size --arg q 'mutation($s: Int!) { fileUpload(contentType: "image/png", filename: "simulator.png", size: $s) { uploadFile { uploadUrl assetUrl headers { key value } } } }' \
    '{query: $q, variables: {s: $s}}')"
  asset=$(jq -r '.data.fileUpload.uploadFile.assetUrl // empty' "$tmp/answer")
  # The signed address and its headers go to curl in a config file, off the command line.
  jq -r '.data.fileUpload.uploadFile | "url = \"\(.uploadUrl)\"", (.headers[] | "header = \"\(.key): \(.value)\"")' \
    "$tmp/answer" > "$tmp/upload" 2>/dev/null
  code=$(curl -q -s -m 30 -K "$tmp/upload" -X PUT -o /dev/null -w '%{http_code}' -H "Content-Type: image/png" \
    -H "Cache-Control: public, max-age=31536000" --data-binary @"$shot")
  if [[ -n $asset && $code == 2?? ]]; then
    extra+=$'\n\n'"![Simulator]($asset)"
  else
    extra+=$'\n'"- The simulator’s screenshot could not be uploaded"
  fi
fi

body=$description
[[ -n $extra ]] && body+=${body:+$'\n\n'}$'---\n'$extra

# ---- the issue ----
linear "$(jq -nc --arg team "$team_id" --arg t "$title" --arg d "$body" \
  --arg q 'mutation($i: IssueCreateInput!) { issueCreate(input: $i) { success issue { identifier url } } }' \
  '{query: $q, variables: {i: {teamId: $team, title: $t, description: $d}}}')"
number=$(jq -r '.data.issueCreate.issue.identifier // empty' "$tmp/answer")
[[ -n $number ]] || fail other "Linear did not make the issue"
flash checkmark "$number"
exit 0
