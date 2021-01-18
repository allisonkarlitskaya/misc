WTR_DEFAULT_PROJECT='/home/lis/src/cockpit'
WTR_DEFAULT_BRANCH='main'

# find the common gitdir for a given working tree
# returns the empty string if it's not a working tree
wtr_absolute_git_common_dir() {
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

wtr_find_gitdir() {
    wtr_absolute_git_common_dir . || \
        wtr_absolute_git_common_dir "${WTR_DEFAULT_BRANCH}" || \
        wtr_absolute_git_common_dir "${WTR_DEFAULT_PROJECT}/${WTR_DEFAULT_BRANCH}"
}

wtr_cd() {
    local gitdir="$(wtr_find_gitdir)"
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

wtr_list() {
    local gitdir="$(wtr_find_gitdir)"
    if test -z "${gitdir}"; then
        return 1
    fi

    git --git-dir="${gitdir}" worktree list

}

wtr_ls() {
    local gitdir="$(wtr_find_gitdir)"
    if test -z "${gitdir}"; then
        return 1
    fi

    (
      # use the user's ls alias
      shopt -sq expand_aliases
      ls "$@" "${gitdir}/../.."
    )
}

wtr_check() {
    local gitdir="$(wtr_find_gitdir)"
    local topdir="$(realpath "${gitdir}/../..")"

    for file in "${topdir}"/*; do
        if test ! -d "${file}"; then
            echo "${file} is not a directory"
            continue
        fi
        local filegitdir="$(wtr_absolute_git_common_dir "${file}")"
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
            . ~/wtr.sh
            ;;

        ls)
            shift
            wtr_ls "$@"
            ;;

        list)
            wtr_list
            ;;

        check)
            wtr_check
            ;;

        cd)
            shift
            wtr_cd "$@";
            ;;
        *)
            echo 'unknown command'
            ;;
    esac
}
