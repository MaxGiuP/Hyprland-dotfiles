function __qs_console_emit_nav --argument token
    printf '\e]2;%s\a' $token
    commandline -f repaint
end

function __qs_console_left
    if commandline --paging-mode
        commandline -f backward-char
        return
    end

    if commandline --search-mode
        commandline -f backward-char
        return
    end

    set -l cursor (commandline --cursor)
    if test "$cursor" -le 0
        __qs_console_emit_nav __QS_PREV__
    else
        commandline -f backward-char
    end
end

function __qs_console_right
    if commandline --paging-mode
        commandline -f forward-char
        return
    end

    if commandline --search-mode
        commandline -f forward-char
        return
    end

    set -l cursor (commandline --cursor)
    set -l buffer (commandline --current-buffer)
    set -l buffer_length (string length -- "$buffer")
    if test "$cursor" -ge "$buffer_length"
        __qs_console_emit_nav __QS_NEXT__
    else
        commandline -f forward-char
    end
end

bind -M default left __qs_console_left
bind -M insert left __qs_console_left
bind -M default right __qs_console_right
bind -M insert right __qs_console_right
