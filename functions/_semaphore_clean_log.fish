function _semaphore_clean_log --description 'Strip ANSI/OSC escapes and progress-bar noise from a Semaphore job log on stdin'
    # Reads a raw `sem logs <id>` dump on stdin, writes cleaned text to stdout.
    # perl, not sed: BSD sed has no \x1b escape.
    #
    # CRs are deleted rather than converted to newlines: Semaphore emits bare
    # CRs mid-content (they'd split real output lines in half). Progress bars
    # therefore collapse into one long line, which the unanchored filter below
    # discards wholesale.
    perl -pe '
        s/\e\][^\a]*\a//g;            # OSC (window titles etc.)
        s/\e\[[0-9;?]*[a-zA-Z]//g;    # all CSI, not just SGR colours
        s/\e[()][0-9A-B]//g;          # charset selection
        s/\r//g;
    ' \
        | grep -Ev '[0-9.]+ ?[KMG]iB.*[0-9]+ ?%' \
        | perl -pe 's/^(.{2000}).*$/$1 … [line truncated]/' \
        | cat -s
end
