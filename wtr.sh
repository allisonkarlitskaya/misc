WTR_DEFAULT_SRCDIR=~/src
WTR_DEFAULT_PROJECT='cockpit'
WTR_DEFAULT_BRANCH='main'

# find the common gitdir for a given working tree
# returns the empty string if it's not a working tree
_wtr_absolute_git_common_dir() {
    # we have --git-dir, --absolute-git-dir, --git-common-dir,
    # but no --absolute-git-common-dir
    local relative="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)"
    if test -z "${relative}"; then
        return 1
    fi
    pushd "$1" >/dev/null
    realpath "${relative}"
    popd >/dev/null
}

_wtr_find_gitdir() {
    _wtr_absolute_git_common_dir . || \
        _wtr_absolute_git_common_dir "${WTR_DEFAULT_BRANCH}" || \
        _wtr_absolute_git_common_dir "${WTR_DEFAULT_SRCDIR}/${WTR_DEFAULT_PROJECT}/${WTR_DEFAULT_BRANCH}"
}

_wtr_cd() {
    local gitdir="$(_wtr_find_gitdir)"
    if test -z "${gitdir}"; then
        return 1
    fi

    local topdir="$(realpath "${gitdir}/../..")"
    local worktree="${topdir}/$1"

    if test ! -d "${worktree}"; then
        git --git-dir "${gitdir}" worktree add "${worktree}"
    fi
    cd "${worktree}"
}

_wtr_list() {
    local gitdir="$(_wtr_find_gitdir)"
    if test -z "${gitdir}"; then
        return 1
    fi

    git --git-dir="${gitdir}" worktree list

}

_wtr_ls() {
    local gitdir="$(_wtr_find_gitdir)"
    if test -z "${gitdir}"; then
        return 1
    fi

    (
      # use the user's ls alias
      shopt -sq expand_aliases
      ls "$@" "${gitdir}/../.."
    )
}

_wtr_check() {
    local gitdir="$(_wtr_find_gitdir)"
    local topdir="$(realpath "${gitdir}/../..")"

    for file in "${topdir}"/*; do
        if test ! -d "${file}"; then
            echo "${file} is not a directory"
            continue
        fi
        local filegitdir="$(_wtr_absolute_git_common_dir "${file}")"
        if test -z "${filegitdir}"; then
            echo "${file} is not a git working tree"
            continue
        fi
        if test ! ${filegitdir} -ef ${gitdir}; then
            echo "${file} isn't a working tree of the same repository"
            continue
        fi
        local expected_branch="$(basename "${file}")"
        local actual_branch="$(git -C "${file}" symbolic-ref --short HEAD)"
        if test "${expected_branch}" != "${actual_branch}"; then
            echo "${file} is on branch ${actual_branch}, not ${expected_branch}"
        fi
    done
}

wtr() {
    case "$1" in
        reload)
            if test -n "${BASH_VERSION}" -a -n "${BASH_SOURCE}"; then
                echo "Sourcing ${BASH_SOURCE}"
                . "${BASH_SOURCE}"
            else
                echo "Don't know how to find script source"
            fi
            ;;

        ls)
            shift
            _wtr_ls "$@"
            ;;

        list)
            _wtr_list
            ;;

        check)
            _wtr_check
            ;;

        cd)
            shift
            _wtr_cd "$@";
            ;;
        *)
            echo 'unknown command'
            ;;
    esac
}

_wtr_complete_cd() {
    test "${COMP_CWORD}" = 2 || return 1
    local gitdir="$(_wtr_find_gitdir)"
    test -n "${gitdir}" || return 1
    local branches="$(git --git-dir="${gitdir}" for-each-ref --format='%(refname:lstrip=-1)')"
    compgen -W "${branches}" "$2"
}

_wtr_complete() {
    #echo $1 $2 $3
    #set | grep ^COMP
    if test "${COMP_CWORD}" = "1"; then
        COMPREPLY=($(compgen -W "reload ls list check cd" "$2"))
    else
        cmd="${COMP_WORDS[1]}"
        if test "$(type -t "_wtr_complete_${cmd}")" = "function"; then
            COMPREPLY=($("_wtr_complete_${cmd}" "wtr ${cmd}" "$2" "$3"))
        fi
    fi
}

complete -F _wtr_complete wtr
