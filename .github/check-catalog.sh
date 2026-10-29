#!/usr/bin/env bash
# Checks that catalog.json and the app folders agree: every app in the catalog has
# its folder with install.sh, run.sh and README.md, and every folder with an
# install.sh is in the catalog. Run from the repository root.
set -euo pipefail

fail=0
complain() {
  echo "error: $*" >&2
  fail=1
}

# The catalog's own shape: what `selan app` reads.
jq -e '
  (.apps | type == "array" and length > 0)
  and all(.apps[];
    (.name | type == "string" and test("^[a-z][a-z0-9-]*$"))
    and (.description | type == "string" and length > 0)
    and (.homepage | type == "string" and startswith("https://"))
    and (.needs | type == "array" and all(.[]; type == "string")))
  and ([.apps[].name] | length == (unique | length))
' catalog.json >/dev/null || complain "catalog.json: every app needs a unique name, a description, an https homepage and a needs list"

for name in $(jq -r '.apps[].name' catalog.json); do
  for file in install.sh run.sh README.md; do
    [ -f "$name/$file" ] || complain "catalog.json lists $name, but $name/$file is missing"
  done
done

for script in */install.sh; do
  name=${script%/install.sh}
  jq -e --arg name "$name" 'any(.apps[]; .name == $name)' catalog.json >/dev/null \
    || complain "$name/ has an install.sh but is not in catalog.json"
done

# The rules every script keeps, as far as a grep can tell.
for script in */install.sh */run.sh; do
  [ -x "$script" ] || complain "$script is not executable"
  [ "$(head -n 1 "$script")" = "#!/usr/bin/env bash" ] || complain "$script does not start with #!/usr/bin/env bash"
  grep -qx 'set -euo pipefail' "$script" || complain "$script has no set -euo pipefail"
done

exit "$fail"
