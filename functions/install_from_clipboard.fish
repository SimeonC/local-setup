function install_from_clipboard
    set -l legacy_peer_deps_flag
    if contains -- '--legacy-peer-deps' $argv
        set legacy_peer_deps_flag '--legacy-peer-deps'
    end
    set dir (pwd)
    while test ! -f $dir/package.json
        set dir (dirname $dir)
        if test $dir = /
            echo "No package.json found"
            return 1
        end
    end
    set pkgfile $dir/package.json
    set dep_pkgs
    set dev_pkgs
    set -l clipboard_content (pbpaste)
    set lines (string split "\n" -- $clipboard_content)

    set -l pkgs
    # First, extract from install command lines
    for line in $lines
        set -l match (string match -r '^(npm install|yarn add) ([^ ]+)$' -- $line)
        if test $status -eq 0
            set pkgs $pkgs $match[3]
        end
    end
    # If no install command lines, try to extract all package@version patterns from the clipboard
    if test (count $pkgs) -eq 0
        set -l matches (string match -ar -r '@?[^@\s,]+(?:/[^@\s,]+)?@[0-9]+\.[0-9]+\.[0-9]+' -- $clipboard_content)
        for pkg in $matches
            set pkg (string trim $pkg)
            set pkgs $pkgs $pkg
        end
    end

    for pkgver in $pkgs
        set pkgname (string replace -r '@[^@]+$' '' -- $pkgver)
        set ver (string match -r '@([^@]+)$' -- $pkgver | string replace -r '^@' '')
        if jq -e ".dependencies | has(\"$pkgname\")" $pkgfile > /dev/null
            set dep_pkgs $dep_pkgs $pkgver
        end
        if jq -e ".devDependencies | has(\"$pkgname\")" $pkgfile > /dev/null
            set dev_pkgs $dev_pkgs $pkgver
        end
    end

    if test (count $dep_pkgs) -gt 0
        echo Installing dependencies: $dep_pkgs
        npm install $legacy_peer_deps_flag $dep_pkgs
    end
    if test (count $dev_pkgs) -gt 0
        echo Installing devDependencies: $dev_pkgs
        npm install --save-dev $legacy_peer_deps_flag $dev_pkgs
    end
end

