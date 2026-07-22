function prclaude --description 'Feed unresolved PR review threads into a Claude /plan session'
    # --- 0. Refuse to nest inside an existing Claude Code session ----------
    # prclaude launches an interactive `claude` /plan session; nesting it inside
    # Claude Code routes through the stream-json wrapper and crashes on exit.
    if set -q CLAUDECODE
        echo "❌ prclaude launches an interactive Claude /plan session, which can't nest inside an existing Claude Code session." >&2
        echo "   Open a plain terminal and run it there." >&2
        return 1
    end

    # --- 1. Validate arg ---------------------------------------------------
    if test (count $argv) -ne 1
        echo "❌ Usage: prclaude <pr-url>" >&2
        return 1
    end

    if not string match -rq 'github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/pull/(?<number>\d+)' -- $argv[1]
        echo "❌ Not a valid GitHub PR URL: $argv[1]" >&2
        echo "   Expected: https://github.com/<owner>/<repo>/pull/<number>" >&2
        return 1
    end

    if not command -q gh
        echo "❌ 'gh' (GitHub CLI) is not installed." >&2
        return 1
    end

    if not _is_git_repo
        echo "❌ Not inside a git repository." >&2
        return 1
    end

    # --- 2. Fetch unresolved threads (deterministic, GraphQL) --------------
    set -l gql 'query($owner:String!,$repo:String!,$pr:Int!){
      repository(owner:$owner,name:$repo){pullRequest(number:$pr){
        reviewThreads(first:100){nodes{
          isResolved isOutdated path line startLine
          comments(first:50){nodes{body author{login} url}}}}}}}'

    set -l tmpjson (mktemp)
    set -l tmperr (mktemp)
    if not gh api graphql -f query=$gql -F owner=$owner -F repo=$repo -F pr=$number >$tmpjson 2>$tmperr
        echo "❌ Failed to fetch review threads:" >&2
        cat $tmperr >&2
        rm -f $tmpjson $tmperr
        return 1
    end

    set -l unresolved_count (jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' $tmpjson)

    # --- 3. No unresolved threads -> done ----------------------------------
    if test "$unresolved_count" -eq 0
        echo "✅ No unresolved review threads on PR #$number"
        rm -f $tmpjson $tmperr
        return 0
    end

    # Render markdown deterministically (not Claude's job). `clean` strips
    # bot-comment noise (HTML comments, <div>/<details>/<picture> blocks with
    # base64 links, <sup> footers, stray tags) so only the reviewer's concern
    # reaches the prompt.
    set -l threads_markdown (jq -r '
      def clean:
          gsub("(?s)<!--.*?-->"; "")
        | gsub("(?s)<details[^>]*>.*?</details>"; "")
        | gsub("(?s)<div[^>]*>.*?</div>"; "")
        | gsub("(?s)<picture[^>]*>.*?</picture>"; "")
        | gsub("(?s)<sup>.*?</sup>"; "")
        | gsub("<[^>]+>"; "")
        | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")
        | gsub("\n[ \t]*\n([ \t]*\n)+"; "\n\n");
      .data.repository.pullRequest.reviewThreads.nodes
      | map(select(.isResolved == false))
      | .[]
      | "### \(.path)\(if .line then ":\(.line)" elif .startLine then ":\(.startLine)" else "" end)\(if .isOutdated then " [OUTDATED]" else "" end)\n"
        + (.comments.nodes | map("**@\(.author.login // "unknown")**:\n\(.body | clean)\n\n(\(.url))") | join("\n\n"))
        + "\n" ' $tmpjson | string collect)
    rm -f $tmpjson $tmperr

    echo "📋 Found $unresolved_count unresolved review thread(s) on PR #$number"

    # --- 4. Smart branch check ---------------------------------------------
    set -l head (gh pr view $argv[1] --json headRefName -q .headRefName)
    if test -z "$head"
        echo "❌ Could not determine PR head branch." >&2
        return 1
    end
    set -l current (git branch --show-current)

    if test "$current" = "$head"
        echo "📥 On branch '$head' — syncing..."
        git fetch origin $head
        if not git merge --ff-only @{u} 2>/dev/null
            echo "⚠️  Could not fast-forward (local commits or divergence). Continuing without sync." >&2
        end
    else
        echo "🔀 PR branch is '$head', you're on '$current'."
        read -l --prompt-str "Use (w)orktree or (c)heckout? [W/c]: " choice
        switch $choice
            case c checkout
                set -l dirty (git status --porcelain)
                if test -n "$dirty"
                    echo "❌ Working tree is dirty — cannot checkout. Re-run and choose worktree, or stash first." >&2
                    return 1
                end
                gh pr checkout $argv[1]; or return 1
            case w worktree ''
                set -l wt_path (dirname $PWD)/(basename $PWD)-pr$number
                git fetch origin $head
                if not git worktree add $wt_path $head
                    echo "❌ Failed to create worktree at $wt_path" >&2
                    return 1
                end
                cd $wt_path
                echo "📂 Working in worktree: $wt_path"
            case '*'
                echo "❌ Unknown choice '$choice' — aborting." >&2
                return 1
        end
    end

    echo "$threads_markdown" > "pr-review-comments.txt"

    # --- 5. Launch Claude in /plan mode ------------------------------------
    claude "/plan Resolve the following unresolved review comments on PR $argv[1].
For each thread, address the reviewer's concern in code (or explain why no change is needed).
All comments are in ./pr-review-comments.txt delete the file once all addressed."
end
