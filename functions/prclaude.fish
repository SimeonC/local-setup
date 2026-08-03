function prclaude --description 'Feed unresolved PR review threads into a Claude /plan session'
    # --- 0. Refuse to nest inside an existing Claude Code session ----------
    # prclaude launches an interactive `claude` /plan session; nesting it inside
    # Claude Code routes through the stream-json wrapper and crashes on exit.
    if set -q CLAUDECODE
        echo "❌ prclaude launches an interactive Claude /plan session, which can't nest inside an existing Claude Code session." >&2
        echo "   Open a plain terminal and run it there." >&2
        return 1
    end

    # --- 1. Preflight ------------------------------------------------------
    # gh + a git repo are needed before we can even detect the PR from the
    # current branch, so these run ahead of arg parsing.
    for dep in gh jq gum
        if not command -q $dep
            echo "❌ '$dep' is not installed." >&2
            return 1
        end
    end

    if not _is_git_repo
        echo "❌ Not inside a git repository." >&2
        return 1
    end

    # --- 2. Resolve the PR URL ---------------------------------------------
    if test (count $argv) -gt 1
        echo "❌ Usage: prclaude [pr-url]" >&2
        return 1
    end

    set -l pr_url
    set -l detected
    if test (count $argv) -eq 1
        set pr_url $argv[1]
        set detected 0
    else
        # No arg: `gh pr view` resolves the PR for the current branch. It fails
        # on detached HEAD, no upstream, or no PR — all handled by the check.
        set pr_url (gh pr view --json url -q .url 2>/dev/null)
        set detected 1
        if test -z "$pr_url"
            echo "❌ No PR found for the current branch. Pass a PR URL: prclaude <pr-url>" >&2
            return 1
        end
    end

    if not string match -rq 'github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/pull/(?<number>\d+)' -- $pr_url
        echo "❌ Not a valid GitHub PR URL: $pr_url" >&2
        echo "   Expected: https://github.com/<owner>/<repo>/pull/<number>" >&2
        return 1
    end

    # --- 3. Fetch unresolved threads (deterministic, GraphQL) --------------
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

    # --- 4. No unresolved threads -> done ----------------------------------
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

    # --- 5. Smart branch check ---------------------------------------------
    # Skipped when the PR was detected from the current branch — we're already
    # in the right working location.
    if test $detected -eq 0
        set -l head (gh pr view $pr_url --json headRefName -q .headRefName)
        test -n "$head"; or begin
            echo "❌ Could not determine PR head branch." >&2
            return 1
        end
        _worktree_or_checkout $head $number; or return 1
    end

    echo "$threads_markdown" > "pr-review-comments.txt"

    # --- 6. Launch Claude in /plan mode ------------------------------------
    claude "/plan Resolve the following unresolved review comments on PR $pr_url.
For each thread, address the reviewer's concern in code (or explain why no change is needed).
All comments are in ./pr-review-comments.txt delete the file once all addressed."
end
