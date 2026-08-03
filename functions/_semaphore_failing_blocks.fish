function _semaphore_failing_blocks --description 'Extract only the non-zero-exit command blocks from a cleaned Semaphore log on stdin'
    # Reads cleaned log text (see _semaphore_clean_log) on stdin. Semaphore
    # delimits every command as:
    #     ✻ <command>
    #     <output...>
    #     exit status: N
    # Emits only the blocks with N != 0, capped, so the agent reads signal only.
    #
    # LC_ALL=C keeps awk byte-oriented: "✻ " is 4 bytes (3 + space), so
    # index()+4 lands on the first character of the command in every locale.
    LC_ALL=C awk '
        function flush(cmd, code,   i, shown) {
            printf "$ %s\n", cmd
            if (n <= 200) {
                for (i = 1; i <= n; i++) print buf[i]
            } else {
                for (i = 1; i <= 40; i++) print buf[i]
                printf "… %d lines elided …\n", n - 200
                for (i = n - 159; i <= n; i++) print buf[i]
            }
            printf "[exit status: %s]\n\n", code
        }
        /^\xe2\x9c\xbb / {
            cmd = substr($0, index($0, "\xe2\x9c\xbb ") + 4)
            n = 0; delete buf
            next
        }
        /^exit status: / {
            code = $3
            last_cmd = cmd; last_code = code; last_n = n
            for (i = 1; i <= n; i++) last_buf[i] = buf[i]
            if (code != "0" && cmd != "Exporting environment variables") {
                flush(cmd, code)
                emitted = 1
            }
            n = 0; delete buf
            next
        }
        { buf[++n] = $0; tail[++t] = $0 }
        END {
            if (emitted) exit 0
            print "> No failing command block found (job may have timed out or been cancelled)."
            print ""
            if (last_cmd != "") {
                n = last_n
                for (i = 1; i <= last_n; i++) buf[i] = last_buf[i]
                flush(last_cmd, last_code)
            }
            print "Last 80 lines:"
            start = t - 79; if (start < 1) start = 1
            for (i = start; i <= t; i++) print tail[i]
        }
    '
end
