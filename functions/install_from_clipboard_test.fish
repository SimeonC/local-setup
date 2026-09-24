#!/usr/bin/env fish

set -l function_dir (dirname (status filename))
set -l repo_root (cd $function_dir/..; and pwd)
source $repo_root/functions/install_from_clipboard.fish
source $repo_root/functions/_pm_detect.fish

function assert_equal --argument-names expected actual label
    if test "$expected" != "$actual"
        printf 'FAIL %s\nexpected: <%s>\nactual:   <%s>\n' $label $expected $actual >&2
        return 1
    end
end

function pbpaste
    printf 'alpha@1.2.3\nbeta@2.3.4\n'
end

set -l fixture (mktemp -d)
mkdir -p $fixture/bin
cd $fixture
printf '{"dependencies":{"alpha":"^1.0.0"},"devDependencies":{"beta":"^2.0.0"}}\n' > $fixture/package.json
touch $fixture/pnpm-lock.yaml
set -gx PATH $fixture/bin $PATH

function jq --wraps jq
    command jq $argv
end

function npm
    printf 'npm:%s\n' (string join ' ' -- $argv) >> $CALLS
end

function pnpm
    printf 'pnpm:%s\n' (string join ' ' -- $argv) >> $CALLS
end

set -gx CALLS $fixture/calls
touch $CALLS

# Override detection to use the fixture's package manager.
function _pm_detect
    printf 'pnpm\n'
end

install_from_clipboard -w
set -l calls (string join '|' < $CALLS)
assert_equal 'pnpm:add -w alpha@1.2.3|pnpm:add -D -w beta@2.3.4' "$calls" 'forward -w to production and dev installs'; or exit 1

printf '' > $CALLS
install_from_clipboard
set calls (string join '|' < $CALLS)
assert_equal 'pnpm:add alpha@1.2.3|pnpm:add -D beta@2.3.4' "$calls" 'unchanged invocation without args'; or exit 1

printf '' > $CALLS
function _pm_detect
    printf 'npm\n'
end
install_from_clipboard --legacy-peer-deps
set calls (string join '|' < $CALLS)
assert_equal 'npm:install --legacy-peer-deps alpha@1.2.3|npm:install --save-dev --legacy-peer-deps beta@2.3.4' "$calls" 'npm legacy peer deps'; or exit 1

rm -rf $fixture
printf 'All install_from_clipboard tests passed.\n'
