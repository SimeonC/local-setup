function sem_ai --description 'Gather failing Semaphore CI context and launch a Claude /plan CI-fix session'
    # --- 0. Refuse to nest inside an existing Claude Code session ----------
    if set -q CLAUDECODE
        echo "❌ sem_ai launches an interactive Claude /plan session, which can't nest inside an existing Claude Code session." >&2
        echo "   Open a plain terminal and run it there." >&2
        return 1
    end

    # --- 1. Validate arg & deps -------------------------------------------
    if test (count $argv) -gt 1
        echo "❌ Usage: sem_ai [semaphore-job-or-workflow-url]" >&2
        return 1
    end

    for dep in sem curl jq gh yq gum
        if not command -q $dep
            echo "❌ '$dep' is not installed." >&2
            return 1
        end
    end
    # Must run before detection — the branch/slug lookup needs a repo.
    if not _is_git_repo
        echo "❌ Not inside a git repository." >&2
        return 1
    end

    # Resolved once; reused by detection and the §6 repo safety check.
    set -l current_slug (gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
    if test -z "$current_slug"
        set current_slug (git remote get-url origin 2>/dev/null | string replace -r '.*[/:]([^/]+/[^/]+?)(\.git)?$' '$1')
    end

    # --- 2. Resolve the Semaphore URL --------------------------------------
    set -l url
    set -l detected 0
    if test (count $argv) -eq 1
        set url $argv[1]
    else
        set detected 1
        # Target the remote branch tip: `gh api .../commits/<branch>/status`
        # resolves the ref server-side, so unpushed local commits are ignored
        # and no fetch is needed.
        # The current branch as origin knows it — a local `theme/x` branch
        # tracking `origin/x` is `x`.
        set -l branch (_current_origin_branch)
        if test -z "$branch"
            # Detached HEAD (e.g. a `--detach` worktree): fall back to the PR head.
            set branch (gh pr view --json headRefName -q .headRefName 2>/dev/null)
        end
        if test -z "$branch"
            echo "❌ Could not determine the current branch. Pass a URL: sem_ai <semaphore-job-or-workflow-url>" >&2
            return 1
        end
        if test -z "$current_slug"
            echo "❌ Could not determine the GitHub repo for this checkout. Pass a URL: sem_ai <semaphore-job-or-workflow-url>" >&2
            return 1
        end
        # Newest Semaphore commit status wins.
        # `contains`, not `test`: fish single-quotes eat one backslash level, so a
        # regex like "semaphoreci\\.com" reaches gojq as an invalid "\." escape.
        # stderr is captured rather than discarded so a real API/jq failure isn't
        # misreported as "no run found".
        set -l gh_err (mktemp)
        set url (gh api repos/$current_slug/commits/$branch/status --jq '
            [.statuses[] | select(.target_url != null and (.target_url | contains("semaphoreci.com")))]
            | sort_by(.created_at) | reverse | .[0].target_url // empty' 2>$gh_err)
        if test -z "$url"
            echo "❌ No Semaphore run found for branch '$branch' on $current_slug." >&2
            echo "   The branch may not be pushed yet, or CI hasn't reported a status." >&2
            if test -s $gh_err
                sed 's/^/   gh: /' $gh_err >&2
            end
            echo "   Pass a URL: sem_ai <semaphore-job-or-workflow-url>" >&2
            rm -f $gh_err
            return 1
        end
        rm -f $gh_err
        echo "🔎 Detected Semaphore run for '$branch': $url"
    end

    # https://<host>/jobs/<id>  |  https://<host>/workflows/<id>[?pipeline_id=<id>]
    if not string match -rq '^https?://(?<host>[^/]+)/(?<kind>jobs|workflows)/(?<id>[0-9a-fA-F-]+)' -- $url
        echo "❌ Not a valid Semaphore job or workflow URL: $url" >&2
        echo "   Expected: https://<host>/jobs/<id> or https://<host>/workflows/<id>" >&2
        return 1
    end
    set -l pipeline_id ''
    if string match -rq 'pipeline_id=(?<pipeline_id>[0-9a-fA-F-]+)' -- $url
        # captured into $pipeline_id
    end

    # --- 3. Extract token & host for the active sem context ----------------
    if not test -f ~/.sem.yaml
        echo "❌ ~/.sem.yaml not found — run `sem connect` / `sem context` first." >&2
        return 1
    end
    set -l active_ctx (yq -r '.["active-context"]' ~/.sem.yaml 2>/dev/null)
    if test -z "$active_ctx"; or test "$active_ctx" = null
        echo "❌ Could not determine active sem context from ~/.sem.yaml." >&2
        return 1
    end
    # `contexts` is a map keyed by context name; index it with the name via env().
    set -l token (SEM_CTX=$active_ctx yq -r '.contexts[env(SEM_CTX)].auth.token' ~/.sem.yaml 2>/dev/null)
    if test -z "$token"; or test "$token" = null
        echo "❌ Could not extract auth token for context '$active_ctx' from ~/.sem.yaml." >&2
        return 1
    end
    set -l ctx_host (SEM_CTX=$active_ctx yq -r '.contexts[env(SEM_CTX)].host' ~/.sem.yaml 2>/dev/null)
    # `sem logs` uses the active context; warn if the URL points at a different host.
    if test -n "$ctx_host"; and test "$ctx_host" != null; and test "$ctx_host" != "$host"
        echo "⚠️  URL host '$host' differs from active sem context host '$ctx_host'. `sem logs` uses the active context." >&2
    end

    set -l api "https://$host/api/v1alpha"
    set -l auth "Authorization: Token $token"

    # --- 4. Resolve target pipeline + target jobs --------------------------
    # rep_env: JSON array of {name,value} env vars from the representative job.
    set -l rep_env ''
    set -l pipeline_name ''
    # target_ids / target_names / target_results are parallel arrays.
    set -l target_ids
    set -l target_names
    set -l target_results

    if test "$kind" = jobs
        set -l job (curl -sf -H $auth "$api/jobs/$id")
        if test -z "$job"
            echo "❌ Failed to fetch job $id from $api." >&2
            return 1
        end
        set rep_env (echo $job | jq -c '.spec.env_vars')
        set -l jname (echo $job | jq -r '.metadata.name')
        set -l jresult (echo $job | jq -r '.status.result')
        set pipeline_id (echo $job | jq -r '.spec.env_vars[] | select(.name=="SEMAPHORE_PIPELINE_ID") | .value')
        # Only the given job is targeted (per decision).
        set target_ids $id
        set target_names $jname
        set target_results $jresult
    else
        set -l wf (curl -sf -H $auth "$api/plumber-workflows/$id")
        if test -z "$wf"
            echo "❌ Failed to fetch workflow $id from $api." >&2
            return 1
        end
        if test -z "$pipeline_id"
            set pipeline_id (echo $wf | jq -r '.workflow.initial_ppl_id')
        end
        set -l pl (curl -sf -H $auth "$api/pipelines/$pipeline_id?detailed=true")
        if test -z "$pl"
            echo "❌ Failed to fetch pipeline $pipeline_id from $api." >&2
            return 1
        end
        set pipeline_name (echo $pl | jq -r '.pipeline.name')
        # Representative job = first job across all blocks.
        set -l rep_job_id (echo $pl | jq -r '[.blocks[].jobs[]] | .[0].job_id')
        if test -n "$rep_job_id"; and test "$rep_job_id" != null
            set -l rjob (curl -sf -H $auth "$api/jobs/$rep_job_id")
            set rep_env (echo $rjob | jq -c '.spec.env_vars')
        end
        # Flatten all blocks, select FAILED jobs.
        set target_ids (echo $pl | jq -r '[.blocks[].jobs[]] | map(select(.result=="FAILED")) | .[].job_id')
        set target_names (echo $pl | jq -r '[.blocks[].jobs[]] | map(select(.result=="FAILED")) | .[].name')
        set target_results (echo $pl | jq -r '[.blocks[].jobs[]] | map(select(.result=="FAILED")) | .[].result')
    end

    # --- 5. No failing jobs -> done ---------------------------------------
    if test (count $target_ids) -eq 0
        echo "✅ No failing jobs"
        return 0
    end

    if test -z "$rep_env"; or test "$rep_env" = null
        echo "❌ Could not read job metadata (env_vars) for branch resolution." >&2
        return 1
    end

    # --- 6. Metadata & branch resolution ----------------------------------
    # Pull all needed env vars from the representative job's env array in one jq pass.
    set -l env_kv (echo $rep_env | jq -r '.[] | "\(.name)=\(.value)"')
    set -l ref_type; set -l pr_branch; set -l git_branch; set -l pr_number
    set -l repo_slug; set -l commit_range; set -l git_sha; set -l workflow_id
    for kv in $env_kv
        set -l k (string split -m1 = -- $kv)[1]
        set -l v (string split -m1 = -- $kv)[2]
        switch $k
            case SEMAPHORE_GIT_REF_TYPE; set ref_type $v
            case SEMAPHORE_GIT_PR_BRANCH; set pr_branch $v
            case SEMAPHORE_GIT_BRANCH; set git_branch $v
            case SEMAPHORE_GIT_PR_NUMBER; set pr_number $v
            case SEMAPHORE_GIT_REPO_SLUG; set repo_slug $v
            case SEMAPHORE_GIT_COMMIT_RANGE; set commit_range $v
            case SEMAPHORE_GIT_SHA; set git_sha $v
            case SEMAPHORE_WORKFLOW_ID; set workflow_id $v
        end
    end

    set -l head
    if test "$ref_type" = pull-request
        set head $pr_branch
    else
        set head $git_branch
        set pr_number ''
    end
    if test -z "$head"; or test "$head" = null
        echo "❌ Could not resolve head branch from job metadata." >&2
        return 1
    end

    # --- Repo safety: must be inside the same repo -------------------------
    # ($current_slug resolved in §1.)
    if test -n "$repo_slug"; and test "$repo_slug" != null; and test -n "$current_slug"
        if test (string lower $repo_slug) != (string lower $current_slug)
            echo "❌ Wrong repo: this Semaphore job is for '$repo_slug' but you're in '$current_slug'." >&2
            echo "   cd into the '$repo_slug' checkout and re-run." >&2
            return 1
        end
    end

    echo "📋 "(count $target_ids)" failing job(s) on branch '$head': $target_names"

    # --- 7. Gather logs ----------------------------------------------------
    # Extracts happen after the checkout (§8) so they land in the final CWD;
    # here we only fetch and stash them in a temp dir.
    set -l stage (mktemp -d)
    set -l slugs
    set -l previews
    set -l linecounts
    for i in (seq (count $target_ids))
        set -l jid $target_ids[$i]
        set -l jname $target_names[$i]
        echo "📥 Fetching logs for '$jname' ($jid)..."

        # Slugify the job name; Semaphore parallel jobs can share a name, so
        # de-duplicate with a -2, -3, ... suffix.
        set -l slug (string lower -- $jname | string replace -ra '[^a-z0-9]+' '-' | string trim -c '-')
        test -n "$slug"; or set slug job
        if contains -- $slug $slugs
            set -l n 2
            while contains -- "$slug-$n" $slugs
                set n (math $n + 1)
            end
            set slug "$slug-$n"
        end
        set -a slugs $slug

        begin
            echo "# $jname — $target_results[$i]"
            echo "# Job: https://$host/jobs/$jid"
            echo "# Full log: sem logs $jid"
            echo ""
            sem logs $jid 2>/dev/null | _semaphore_clean_log | _semaphore_failing_blocks
        end >$stage/$slug.log

        set -a linecounts (wc -l <$stage/$slug.log | string trim)
        # First `$ …` line = the failing command, used as the index preview.
        # Kept as a single element even when absent, so the arrays stay parallel.
        set -l preview (grep -m1 '^\$ ' $stage/$slug.log | string sub -l 160)
        test -n "$preview"; or set preview '(no failing command block — see file)'
        set -a previews "$preview"
    end

    # --- 8. Checkout -------------------------------------------------------
    # Skipped when the run was detected from the current branch — we're already
    # in the right working location.
    if test $detected -eq 0
        if test "$ref_type" = pull-request; and test -n "$pr_number"; and test "$pr_number" != null
            _worktree_or_checkout $head $pr_number; or return 1
        else
            _worktree_or_checkout $head; or return 1
        end
    end

    # --- 9. Write context directory ----------------------------------------
    # ci-failures/ lives in the (possibly new) CWD.
    set -l ctx_dir (pwd)/ci-failures
    if test -e $ctx_dir
        # Only recreate a directory that looks like one of ours — never blind-rm.
        set -l stray (find $ctx_dir -mindepth 1 -maxdepth 1 -not -name '*.log' -not -name README.md -not -name .gitignore)
        if test -d $ctx_dir; and test -z "$stray"
            rm -rf $ctx_dir
        else
            echo "❌ $ctx_dir exists and holds unexpected contents — move it aside and re-run." >&2
            rm -rf $stage
            return 1
        end
    end
    mkdir -p $ctx_dir; or begin
        rm -rf $stage
        return 1
    end
    cp $stage/*.log $ctx_dir/
    rm -rf $stage
    echo '*' >$ctx_dir/.gitignore

    set -l base_hint
    if test -n "$commit_range"; and test "$commit_range" != null
        set base_hint "- Inspect all changes: \`git diff $commit_range\`
- Commits on this branch: \`git log --oneline $commit_range\`"
    else
        set base_hint "- Inspect changes vs the base branch (e.g. \`git log --oneline origin/main..HEAD\` and \`git diff origin/main...HEAD\`)."
    end

    begin
        echo "# Failing Semaphore CI checks"
        echo ""
        echo "- Source URL: $url"
        echo "- Host: $host"
        test -n "$workflow_id"; and echo "- Workflow ID: $workflow_id"
        echo "- Pipeline ID: $pipeline_id"
        test -n "$pipeline_name"; and test "$pipeline_name" != null; and echo "- Pipeline: $pipeline_name"
        echo "- Branch: $head"
        test -n "$pr_number"; and test "$pr_number" != null; and echo "- PR: #$pr_number"
        test -n "$git_sha"; and test "$git_sha" != null; and echo "- Commit SHA: $git_sha"
        echo ""
        echo "## How to inspect the changes"
        echo ""
        echo "$base_hint"
        echo ""
        echo "## Failing jobs"
        echo ""
        for i in (seq (count $slugs))
            echo "- [$target_names[$i]](./$slugs[$i].log) — FAILED, $linecounts[$i] lines"
            echo "  - `$previews[$i]`"
        end
        echo ""
        echo "## Reading these logs"
        echo ""
        echo "Each file contains only the command blocks that exited non-zero, with ANSI escapes"
        echo "and progress-bar noise stripped — not the full job output. For the untruncated"
        echo "original, run \`sem logs <job-id>\` (the job ID is in each file's header)."
    end >$ctx_dir/README.md

    echo "📝 Wrote failing CI context to $ctx_dir/ (index: README.md)"

    # --- 10. Launch Claude in /plan mode ----------------------------------
    set -l pr_note ''
    if test -n "$pr_number"; and test "$pr_number" != null
        set pr_note " (PR #$pr_number)"
    end
    __ai_run "/plan Fix the failing Semaphore CI checks on branch $head$pr_note.
Start with ./ci-failures/README.md — it indexes one extract file per failing job, plus how to inspect the changes.
Diagnose each failure, fix in code, and explain. Delete the ./ci-failures/ directory once all addressed."
end
