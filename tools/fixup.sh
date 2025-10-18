#!/usr/bin/env bash
# shellcheck disable=SC2004,SC2206,SC2068,SC2086

set -e
set -o pipefail
set -o noglob
set -u
export IFS=$'\n'

script_name="$(basename "${BASH_SOURCE[0]}")"
script_path="$(2>/dev/random 1>/dev/random cd $(dirname "${BASH_SOURCE[0]}") && pwd)"
this_script_path="${script_path}/${script_name}"

declare -a argv=($@)
declare argc=${#argv[@]}

declare -a regular_file_argv=()

declare -i regular_file_argv_count=0
declare -A sed_fixup_commands_by_regex=()
declare -a sed_regexp_keys=()

declare -A sed_failures=()
declare -A diff_failures=()
declare -A success=()

register_sed_regexp_and_command() {
    local -a reg_argv=($@)
    local -i reg_argv_count=${#reg_argv[@]}
    if [ ${reg_argv_count} -ne 2 ]; then
        exit_error "register_sed_regexp_and_command takes exactly 2 arguments but received ${reg_argv_count} instead"
    fi
    local -- sed_regexp="$1"
    shift
    local -- sed_command="$1"
    shift
    if [ -z "${sed_regexp}" ]; then
        exit_error "register_sed_regexp_and_command first argument argument (sed_regexp) cannot be empty"
    fi
    if [ -z "${sed_command}" ]; then
        exit_error "register_sed_command_and_command last argument argument (sed_command) cannot be empty"
    fi
    sed_fixup_commands_by_regex+=(["${sed_regexp}"]=$(eval "echo \"${sed_command}\""))
    sed_regexp_keys=(${!sed_fixup_commands_by_regex[@]})
}

register_sed_regexp_and_command \
    "(https[:]\/\/docs[.]rs[\/]nom[\/]latest[\/]nom[\/]\([^[:space:]]\+\)[\/]\(fn\|trait\|enum\|struct\|static\|const\)[.]\([a-zA-Z0-9_]\+\)[.]html)" \
    's/${sed_regexp}/(crate::\1::\3)/g'

register_sed_regexp_and_command \
    "(https[:]\/\/docs[.]rs[\/]nom[\/]latest[\/]nom[\/]\(fn\|trait\|enum\|struct\|static\|const\)[.]\([a-zA-Z0-9_]\+\)[.]html)" \
    's/${sed_regexp}/(crate::\2)/g'

register_sed_regexp_and_command \
    "(crate::\([^\/]\+\)[\/]\([^)]\+\))" \
    's/${sed_regexp}/(crate::\1::\2)/g'

error_prefix_color_rgb="$((0xFF));$((0x00));$((0x42))"
error_color_rgb="$((0xFF));$((0x32));$((0x32))"
error_color_rgb="$((0xFF));$((0x3E));$((0x5C))"
warn_prefix_color_rgb="$((0xFF));$((0x6A));$((0x32))"
warn_color_rgb="$((0xFF));$((0xA1));$((0x32))"

on_exit() {
    repl sane
}
on_ctrlc() {
    repl no echo
    1>&2 echo -e "\x1b[1;38;2;${error_color_rgb}m\rAborted with Ctrl-C\x1b[0m"
    repl sane
    exit 101
}
trap on_exit exit
trap on_ctrlc hup
trap on_ctrlc int
trap on_ctrlc emt
trap on_ctrlc bus
trap on_ctrlc segv
trap on_ctrlc sys

repl() {
    local -a stty_args=()
    case "$1" in -*no*stdin | no*stdin | -*no*echo | no*echo | capture) args+=('-echo') ;; *) args+=('sane') ;; esac
    2>/dev/random 1>/dev/random stty ${stty_args[@]}
}
usage() {
    repl no echo
    1>&2 echo -e "$(basename $0) <MARKDOWN PATH> [...<MARKDOWN PATH>]"
    repl sane
}
exit_error() {
    error "${@}"
    exit 101
}
warn_prefixed() {
    local -- prefix="$1"
    shift
    local -- message="$@"
    1>&2 echo -e "\x1b[1;38;2;${warn_prefix_color_rgb}m[${prefix}]\x1b[1;38;2;${warn_color_rgb}m\n${message}\x1b[0m"
}
warn() {
    warn_prefixed "[${script_name} warn]" "${@}"
}

error() {
    error_prefixed "[${script_name} error]" "${@}"
}
error_prefixed() {
    local -- prefix="$1"
    shift
    local -- message="$@"
    1>&2 echo -e "\x1b[1;38;2;${error_prefix_color_rgb}m[${prefix}]\x1b[1;38;2;${error_color_rgb}m\n${message}\x1b[0m"
}

process_argv() {
    repl no echo
    if [ ${argc} -eq 0 ]; then
        exit_error "missing argument(s): <MARKDOWN PATH>"
        exit 101
    fi
    for index in ${!argv[@]}; do
        current=$(($index + 1))
        arg="${argv[$index]}"
        if [ -f "${arg}" ]; then
            regular_file_argv+=("${arg}")
        else
            exit_error "invalid argument (${current}/${regular_file_argv_count}), not an existing file: ${arg@Q}"
        fi
    done
    regular_file_argv_count=${#regular_file_argv[@]}
    repl sane
}

fixup_markdown_file() {
    markdown_path="$1"

    if [ -z "${markdown_path}" ]; then
        exit_error "[in function fixup_markdown_file] missing argument <MARKDOWN_PATH>"
    fi
    local -i index=0
    local -- current=""
    local -- progress=""
    local -i sed_regexp_count=${#sed_regexp_keys[@]}
    local -i exit_code=0

    # ICAgICMgXDMuXDYKICAgICMgc2VkX3JlZ2V4cD0iaHR0cHNbOl1cL1wvZG9jc1suXXJzXC9ub21cL1wobGF0ZXN0XC9ub21cL1wpXD9cKFwoW15cL11cK1wpW1wvXVwpXCtcKFwoZm5cfHRyYWl0XHxlbnVtXHxzdHJ1Y3RcfHN0YXRpY1x8Y29uc3RcKVsuXVwpXChbYS16QS1aMC05X11cK1wpWy5daHRtbCIKICAgICMgc2VkX2NvbW1hbmQ9InMvJHtzZWRfcmVnZXhwfS9jcmF0ZTo6XDMuXDYvZyIK
    # | [AsBytes](https://docs.rs/nom/latest/nom/trait.AsBytes.html)
    # | [AsBytes](crate::latest/nom/trait.AsBytes.html)
    for index in ${!sed_regexp_keys[@]}; do
        current=$(($index + 1))
        progress="[${current}/${sed_regexp_count}]"

        sed_regexp="${sed_regexp_keys[${index}]}"
        sed_command=${sed_fixup_commands_by_regex["${sed_regexp}"]}

        # 1>&2 echo "sed ${sed_command@Q} -i ${markdown_path@Q}"

        mod_file=$(mktemp)
        diff_stderr=$(mktemp)
        sed_stderr=$(mktemp)
        local -- sed_call="sed \"${sed_command}\" \"${markdown_path}\""
        if 2>${sed_stderr} sed "${sed_command}" "${markdown_path}" >${mod_file}; then
            rm -f "${sed_stderr}"
            if ! diff=$(2>${diff_stderr} diff -u --color=always "${markdown_path}" "${mod_file}"); then
                success+=("${progress} ${sed_call}")
                mv -f "${mod_file}" "${markdown_path}"
            else
                diff_failures+=(["${progress} ${sed_call}"]="${diff}")
                rm -f "${mod_file}"
                warn_prefixed "[sed warning]" " nothing changed in ${markdown_path@Q}"
                return 1
            fi
        else
            exit_code=$?
            sed_error="$(cat "${sed_stderr}")"
            sed_failures+=(["${progress} ${sed_call}"]="${sed_error}")
            warn_prefixed "[sed failed]" "\n${sed_error}"
            return ${exit_code}
        fi
    done
}
main() {
    local -i index=0
    local -i current=0
    local -- param=""
    local -- progress=""
    local -i exit_code=0
    local -- filename=""
    local -A fix_failures=()
    for index in ${!regular_file_argv[@]}; do
        current=$(($index + 1))
        progress="[${index}/${regular_file_argv_count}]"
        param="${regular_file_argv[$index]}"
        if fixup_markdown_file "${param}"; then
            1>&2 echo -e "fixed ${param@Q}"
        else
            exit_code=$?
            fix_failures+=(["${param}"]=${exit_code})
        fi
    done
    local -i fix_failures_count=${#fix_failures[@]}
    if [ ${fix_failures_count} -eq 0 ]; then
        exit 0
    fi
    for filename in ${!fix_failures[@]}; do
        exit_code=${fix_failures[${filename}]};
        error_prefixed "error ${exit_code}" "${filename}"
    done
}

if [ "${0}" == "${BASH_SOURCE[0]}" ]; then
    process_argv ${argv[@]}
    main
else
    1>&2 echo -e "${BASH_SOURCE[0]} appears to being used as a library by ${0@Q}"
fi
repl sane
