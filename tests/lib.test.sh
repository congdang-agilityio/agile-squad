# shellcheck shell=bash disable=SC2016,SC2034
# lib.sh: YAML subset parser, cfg, issue_args
R="$(new_repo)"; squad_config "$R"; cd "$R" || exit 1
# shellcheck source=/dev/null
source "$S/lib.sh"
load_config
eq "template parses; parallel.max_parallel_dev" "$(cfg .parallel.max_parallel_dev)" "2"
eq "flow map as JSON" "$(cfg .limits.pr_max_lines)" '{"XS":50,"S":150,"M":300}'
eq "flow list keeps quoted globs" "$(cfg '.limits.pr_size_exclude[0]')" "**/*.test.*"
eq "comment after a value is stripped" "$(cfg .deploy.platform)" "railway"
eq "missing key prints nothing" "$(cfg .nope.nothing)" ""
eq "true stays true" "$(cfg .merge.require_ci)" "true"
CFG_JSON='{"merge":{"require_ci":false}}'
eq "false stays false (merge.require_ci: false must work)" "$(cfg .merge.require_ci)" "false"
eq "nested models map" "$(load_config; cfg '.models.review.S')" "opus"
eq "issue_args accepts #, commas and spaces" "$(issue_args "#36,#63" 70 "x" | tr '\n' ' ')" "36 63 70 "
printf 'a: "x # not a comment"\nb:\n  - one\n  - "two"\n' > "$R/t.yml"
eq "hash inside quotes is not a comment" "$(yaml_to_json "$R/t.yml" | jq -r .a)" "x # not a comment"
eq "block list" "$(yaml_to_json "$R/t.yml" | jq -c .b)" '["one","two"]'
printf 'a: 1\n   b: 2\n' > "$R/bad.yml"
check "bad indentation is an error" '! yaml_to_json "$R/bad.yml" >/dev/null 2>&1'
cd / && rm -rf "$(dirname "$R")"
