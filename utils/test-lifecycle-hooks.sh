#!/bin/sh
# Verify gen-ctl-io emits the after-copy / after-destroy hook glue
# declared via (after-copy ...) / (after-destroy ...) in define-class.
set -e

srcdir=${srcdir:-.}
top_srcdir=${top_srcdir:-$srcdir/..}
top_builddir=${top_builddir:-$srcdir/..}

gen=${top_builddir}/utils/gen-ctl-io
spec=${srcdir}/lifecycle-hooks-spec.scm

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

"$gen" --c-only --header -o "$tmpdir/test-io.h" "$spec" "$top_srcdir"
"$gen" --c-only --code   -o "$tmpdir/test-io.c" "$spec" "$top_srcdir"

check () {
    if ! grep -F -q "$1" "$2"; then
        echo "FAIL: expected '$1' in $2" >&2
        echo "----- $2 -----" >&2
        cat "$2" >&2
        exit 1
    fi
}

check "extern void hook_after_copy(hooked *);"    "$tmpdir/test-io.h"
check "extern void hook_after_destroy(hooked *);" "$tmpdir/test-io.h"
check "hook_after_copy(o);"     "$tmpdir/test-io.c"
check "hook_after_destroy(&o);" "$tmpdir/test-io.c"

echo "PASS: gen-ctl-io emits after-copy / after-destroy hooks"
