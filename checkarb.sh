#!/system/bin/sh

# ============================================
# License
#=============================================
# MIT License
# Copyright (c) 2026 Dere
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ============================================

#####DefineVariable
ACTIVE_SLOT=""
WORK_DIR="/data/local/tmp/checkarb"
OUTPUT_FILE="xbl_config.img"
BIN_ZIP_HASH="d203b96fdf341a52d47171853bb5898342c5b5802eec70ce701aa276f19ac786"
MARKER="__ARCHIVE_FOLLOWS__"
IS_MEDIATEK=0
BUSYBOX_CMD="busybox"
CANDIDATE_BASES="/dev/block/bootdevice/by-name /dev/block/platform/*/by-name /dev/block/by-name"
#####End

#####Fun
run_as_su() {
    if command -v su >/dev/null 2>&1; then
        su -c "$1"
    else
        echo "Error: Root privileges required but su command not found" >&2
        exit 1
    fi
}

remove_work_dir() {
    if command -v su >/dev/null 2>&1; then
        run_as_su "rm -rf \"$WORK_DIR\""
    else
        rm -rf "$WORK_DIR" 2>/dev/null
    fi
}

cleanup() {
    remove_work_dir
}

clear_screen() {
    printf "\033[2J\033[H"
}

handle_error() {
    msg="$1"
    code="$2"
    output="$3"
    echo "Error: $msg (exit code $code)" >&2
    if [ -n "$output" ]; then
        echo "Raw output:" >&2
        echo "$output" >&2
    fi
    build_version=$(getprop ro.build.display.id 2>/dev/null)
    echo "Device Build version: ${build_version:-Unknown}" >&2
    exit $code
}

check_file_exists() {
    path="$1"
    run_as_su "test -e \"$path\"" || return 1
    return 0
}

getAndroidShellType() {
    getAndroidShellType_detected="unknown"
    
    if [ -n "${KSH_VERSION}" ]; then
        case "${KSH_VERSION}" in
            *MIRBSD*|*@\(#\)MIRBSD*)
                getAndroidShellType_detected="mksh"
                ;;
            *)
                getAndroidShellType_detected="ksh"
                ;;
        esac
    elif [ -n "${BASH_VERSION}" ]; then
        getAndroidShellType_detected="bash"
    elif (eval 'echo "${.sh.version}"' >/dev/null 2>&1); then
        getAndroidShellType_detected="mksh"
    elif [ -L "/system/bin/sh" ]; then
        if command -v readlink >/dev/null 2>&1; then
            getAndroidShellType_sh_target=$(readlink "/system/bin/sh" 2>/dev/null)
        else
            getAndroidShellType_sh_target=$(LC_ALL=C ls -l "/system/bin/sh" 2>/dev/null | awk '{print $NF}')
        fi
        getAndroidShellType_target_name=$(basename "${getAndroidShellType_sh_target}" 2>/dev/null)
        
        case "${getAndroidShellType_target_name}" in
            mksh)
                getAndroidShellType_detected="mksh"
                ;;
            ash)
                getAndroidShellType_detected="ash"
                ;;
            bash)
                getAndroidShellType_detected="bash"
                ;;
            busybox)
                if command -v busybox >/dev/null 2>&1; then
                    if busybox 2>&1 | grep 'ash' >/dev/null 2>&1; then
                        getAndroidShellType_detected="ash"
                    elif busybox 2>&1 | grep 'bash' >/dev/null 2>&1; then
                        getAndroidShellType_detected="bash"
                    fi
                fi
                ;;
        esac
    else
        if (eval '[[ 1 -eq 1 ]]' >/dev/null 2>&1); then
            getAndroidShellType_detected="bash"
        else
            getAndroidShellType_detected="ash"
        fi
    fi
    
    echo "${getAndroidShellType_detected}"
}

checkShell() {
    checkShell_shell_type=$(getAndroidShellType)
    case "${checkShell_shell_type}" in
        mksh|ash|ksh)
            return 0
            ;;
        bash)
            echo "Current shell is bash, script does not support bash. If you are using MT or other terminal apps, please use system environment to execute" >&2
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

check_su_exists() {
    command -v su >/dev/null 2>&1
}

check_cpu_arch() {
    CPU_ARCH=$(getprop ro.product.cpu.abi 2>/dev/null)
    if [ -z "$CPU_ARCH" ]; then
        CPU_ARCH=$(uname -m 2>/dev/null)
    fi
    CPU_ARCH=$(echo "$CPU_ARCH" | tr '[:upper:]' '[:lower:]')
    case "$CPU_ARCH" in
        *arm*|*aarch64*)
            readonly CPU_ARCH
            echo "Detected ARM architecture: $CPU_ARCH"
            ;;
        *)
            echo "Error: Unsupported CPU architecture ($CPU_ARCH), this script only supports ARM32/ARM64 devices." >&2
            exit 1
            ;;
    esac
}

check_if_mediatek() {
    IS_MEDIATEK=0
    mtk_platform=$(getprop ro.mediatek.platform 2>/dev/null)
    board_platform=$(getprop ro.board.platform 2>/dev/null)
    chipname=$(getprop ro.chipname 2>/dev/null)
    
    if [ -n "$mtk_platform" ]; then
        case "$mtk_platform" in
            *[mM][tT]*|*[Mm][Tt]*) IS_MEDIATEK=1 ;;
        esac
    fi
    if [ $IS_MEDIATEK -eq 0 ] && [ -n "$board_platform" ]; then
        case "$board_platform" in
            [mM][tT]*|[Mm][Tt]*) IS_MEDIATEK=1 ;;
        esac
    fi
    if [ $IS_MEDIATEK -eq 0 ] && [ -n "$chipname" ]; then
        case "$chipname" in
            *[dD][iI][mM][eE][nN][sS][iI][tT][yY]*) IS_MEDIATEK=1 ;;
        esac
    fi
}

find_busybox() {
    search_path="/data/adb"
    if [ -d "$search_path" ]; then
        found=$(find "$search_path" -type f -name "busybox" -exec test -x {} \; -print 2>/dev/null | head -n 1)
        if [ -n "$found" ] && [ -x "$found" ]; then
            BUSYBOX_CMD="$found"
            echo "Found alternative busybox: $BUSYBOX_CMD" >&2
        fi
    fi
}

get_active_slot() {
    slot=$(getprop ro.boot.slot_suffix 2>/dev/null)
    if [ -z "$slot" ]; then
        slot=$(getprop ro.boot.slot 2>/dev/null)
    fi
    case "$slot" in
        *a*) echo "a" ;;
        *b*) echo "b" ;;
        *) echo "" ;;
    esac
}

gather_xbl_config_partitions() {
    tmp_file="$WORK_DIR/partlist.tmp"
    find_cmd=""
    for candidate in "find" "busybox find" "$BUSYBOX_CMD find"; do
        set -- $candidate
        cmd="$1"
        shift
        if command -v "$cmd" >/dev/null 2>&1; then
            if "$cmd" "$@" /dev/block -maxdepth 0 -iname "xbl_config" 2>/dev/null >/dev/null; then
                find_cmd="$cmd $*"
                break
            fi
        fi
    done
    if [ -n "$find_cmd" ]; then
        run_as_su "$find_cmd /dev/block -iname '*xbl_config*' 2>/dev/null > \"$tmp_file\""
    else
        run_as_su "find /dev/block -name '*xbl_config*' -o -name '*XBL_CONFIG*' 2>/dev/null > \"$tmp_file\""
    fi
    if [ -s "$tmp_file" ]; then
        if command -v sort >/dev/null 2>&1; then
            sort -u "$tmp_file" -o "$tmp_file"
        elif command -v busybox >/dev/null 2>&1 && busybox sort --help >/dev/null 2>&1; then
            busybox sort -u "$tmp_file" -o "$tmp_file"
        elif [ -n "$BUSYBOX_CMD" ] && [ -x "$BUSYBOX_CMD" ] && "$BUSYBOX_CMD" sort --help >/dev/null 2>&1; then
            "$BUSYBOX_CMD" sort -u "$tmp_file" -o "$tmp_file"
        fi
        cat "$tmp_file"
    fi
    rm -f "$tmp_file"
}

select_partition_manually() {
    echo "Scanning all partitions containing xbl_config..." >&2
    part_list=$(gather_xbl_config_partitions)
    count=0
    for p in $part_list; do
        count=$((count + 1))
    done
    if [ $count -eq 0 ]; then
        echo "Error: No xbl_config partition files found" >&2
        return 1
    fi
    echo "Found the following partitions:" >&2
    i=1
    for p in $part_list; do
        printf "  %d) %s\n" $i "$p" >&2
        i=$((i + 1))
    done
    printf "Please enter a number (1-%d): " $count >&2
    read choice
    case "$choice" in
        ''|*[!0-9]*)
            echo "Error: Invalid input" >&2
            return 1
            ;;
        *)
            if [ $choice -lt 1 ] || [ $choice -gt $count ]; then
                echo "Error: Number out of range" >&2
                return 1
            fi
            i=1
            for p in $part_list; do
                if [ $i -eq $choice ]; then
                    echo "$p"
                    return 0
                fi
                i=$((i + 1))
            done
            ;;
    esac
    return 1
}

find_partition_path() {
    partition_basename="$1"
    slot_suffix="$2"
    
    if [ -n "$slot_suffix" ]; then
        for base in $CANDIDATE_BASES; do
            for path in $base; do
                if [ -d "$path" ]; then
                    candidate="${path}/${partition_basename}_${slot_suffix}"
                    if [ -e "$candidate" ]; then
                        echo "$candidate"
                        return 0
                    fi
                fi
            done
        done
    else
        for base in $CANDIDATE_BASES; do
            for path in $base; do
                if [ -d "$path" ]; then
                    candidate="${path}/${partition_basename}"
                    if [ -e "$candidate" ]; then
                        echo "$candidate"
                        return 0
                    fi
                fi
            done
        done
    fi

    found_files=""
    for base in $CANDIDATE_BASES; do
        for path in $base; do
            if [ -d "$path" ]; then
                for file in "$path"/*; do
                    if [ -f "$file" ]; then
                        filename=$(basename "$file")
                        case "$filename" in
                            *xbl_config*)
                                found_files="$found_files $file"
                                ;;
                        esac
                    fi
                done
            fi
        done
    done
    dir_list=$(run_as_su "find /dev/block -type d -name 'by-name' 2>/dev/null")
    for dir in $dir_list; do
        if [ -d "$dir" ]; then
            for file in "$dir"/*; do
                if [ -f "$file" ]; then
                    filename=$(basename "$file")
                    case "$filename" in
                        *xbl_config*)
                            found_files="$found_files $file"
                            ;;
                    esac
                fi
            done
        fi
    done

    for file in $found_files; do
        filename=$(basename "$file")
        suffix=${filename##xbl_config}
        if [ -z "$suffix" ] && [ -z "$slot_suffix" ]; then
            echo "$file"
            return 0
        fi
        if [ "$slot_suffix" = "a" ]; then
            if [ "$suffix" = "_a" ] || [ "$suffix" = "a" ]; then
                echo "$file"
                return 0
            fi
        fi
        if [ "$slot_suffix" = "b" ]; then
            if [ "$suffix" = "_b" ] || [ "$suffix" = "b" ]; then
                echo "$file"
                return 0
            fi
        fi
    done
    return 1
}

prepare_tools() {
    echo "Preparing detection tools..."
    remove_work_dir
    run_as_su "mkdir -p \"$WORK_DIR\"" || {
        echo "Error: Cannot create directory $WORK_DIR" >&2
        exit 1
    }

    script_self="$0"
    line=$(awk "/^${MARKER}$/{print NR; exit}" "$script_self")
    if [ -z "$line" ]; then
        echo "Error: Archive marker not found, please verify script integrity" >&2
        exit 1
    fi

    tmp_zip="$WORK_DIR/bin.zip"
    tail -n +$((line + 1)) "$script_self" | run_as_su "cat > \"$tmp_zip\"" 2>/dev/null || {
        echo "Error: Failed to extract appended data" >&2
        exit 1
    }

    if command -v sha256sum >/dev/null 2>&1; then
        computed_hash=$(run_as_su "sha256sum \"$tmp_zip\"" | cut -d' ' -f1)
    elif command -v busybox >/dev/null 2>&1 && busybox sha256sum --help >/dev/null 2>&1; then
        computed_hash=$(run_as_su "busybox sha256sum \"$tmp_zip\"" | cut -d' ' -f1)
    elif [ -n "$BUSYBOX_CMD" ] && [ -x "$BUSYBOX_CMD" ] && "$BUSYBOX_CMD" sha256sum --help >/dev/null 2>&1; then
        computed_hash=$(run_as_su "$BUSYBOX_CMD sha256sum \"$tmp_zip\"" | cut -d' ' -f1)
    elif command -v openssl >/dev/null 2>&1; then
        computed_hash=$(run_as_su "openssl dgst -sha256 \"$tmp_zip\"" | cut -d' ' -f2)
    else
        computed_hash=""
    fi

    if [ -z "$computed_hash" ]; then
        echo "Error: No available SHA256 tool (requires sha256sum, busybox sha256sum, or openssl)" >&2
        exit 1
    fi

    if [ "$computed_hash" != "$BIN_ZIP_HASH" ]; then
        echo "Error: bin.zip hash verification failed" >&2
        echo "Expected: $BIN_ZIP_HASH" >&2
        echo "Actual: $computed_hash" >&2
        exit 1
    fi
    echo "Hash verification passed."

    if command -v unzip >/dev/null 2>&1; then
        run_as_su "unzip -q -o \"$tmp_zip\" -d \"$WORK_DIR\"" || {
            echo "Error: Failed to extract bin.zip" >&2
            exit 1
        }
    elif command -v busybox >/dev/null 2>&1 && busybox unzip --help >/dev/null 2>&1; then
        run_as_su "busybox unzip -q -o \"$tmp_zip\" -d \"$WORK_DIR\"" || {
            echo "Error: Failed to extract using busybox" >&2
            exit 1
        }
    elif [ -n "$BUSYBOX_CMD" ] && [ -x "$BUSYBOX_CMD" ] && "$BUSYBOX_CMD" unzip --help >/dev/null 2>&1; then
        run_as_su "$BUSYBOX_CMD unzip -q -o \"$tmp_zip\" -d \"$WORK_DIR\"" || {
            echo "Error: Failed to extract using alternative busybox" >&2
            exit 1
        }
    else
        echo "Error: unzip command not found, cannot extract tool package" >&2
        exit 1
    fi

    run_as_su "rm -f \"$tmp_zip\""

    case "$CPU_ARCH" in
        *aarch64*|*arm64*)
            tool_zip="arb_inspector-aarch64-linux-android.zip"
            ;;
        *armv7*|*armeabi*|*arm*)
            tool_zip="arb_inspector-armv7-linux-androideabi.zip"
            ;;
        *)
            echo "Error: Unrecognized ARM architecture variant: $CPU_ARCH" >&2
            exit 1
            ;;
    esac

    if ! run_as_su "test -f \"$WORK_DIR/$tool_zip\""; then
        echo "Error: $tool_zip not found in bin.zip" >&2
        exit 1
    fi

    if command -v unzip >/dev/null 2>&1; then
        run_as_su "unzip -q -o \"$WORK_DIR/$tool_zip\" -d \"$WORK_DIR\"" || {
            echo "Error: Failed to extract $tool_zip" >&2
            exit 1
        }
    elif command -v busybox >/dev/null 2>&1 && busybox unzip --help >/dev/null 2>&1; then
        run_as_su "busybox unzip -q -o \"$WORK_DIR/$tool_zip\" -d \"$WORK_DIR\"" || {
            echo "Error: Failed to extract $tool_zip using busybox" >&2
            exit 1
        }
    elif [ -n "$BUSYBOX_CMD" ] && [ -x "$BUSYBOX_CMD" ] && "$BUSYBOX_CMD" unzip --help >/dev/null 2>&1; then
        run_as_su "$BUSYBOX_CMD unzip -q -o \"$WORK_DIR/$tool_zip\" -d \"$WORK_DIR\"" || {
            echo "Error: Failed to extract $tool_zip using alternative busybox" >&2
            exit 1
        }
    else
        echo "Error: unzip command not found, cannot extract $tool_zip" >&2
        exit 1
    fi

    run_as_su "rm -f \"$WORK_DIR\"/arb_inspector-*.zip"
    run_as_su "chmod 755 \"$WORK_DIR/arb_inspector\"" 2>/dev/null || {
        echo "Error: Cannot set executable permission for arb_inspector" >&2
        exit 1
    }

    echo "Tools preparation completed."
}

ensure_temp_dir() {
    run_as_su "mkdir -p \"$WORK_DIR\"" 2>/dev/null || {
        echo "Error: Cannot create directory $WORK_DIR" >&2
        exit 1
    }
}

fetch_xbl_config() {
    fetch_xbl_config_slot="$1"
    manual_path="$2"
    partition_basename="xbl_config"
    
    if [ -n "$manual_path" ]; then
        partition_path="$manual_path"
    else
        partition_path=$(find_partition_path "$partition_basename" "$fetch_xbl_config_slot")
    fi
    
    if [ -z "$partition_path" ]; then
        echo "Error: Cannot find $partition_basename partition" >&2
        return 1
    fi
    
    fetch_xbl_config_dst="${WORK_DIR}/${OUTPUT_FILE}"
    
    if ! run_as_su "cat '$partition_path' > '$fetch_xbl_config_dst'"; then
        echo "Error: Cannot read partition $partition_path or write to $fetch_xbl_config_dst" >&2
        return 1
    fi

    echo "Successfully copied $(basename $partition_path) to $fetch_xbl_config_dst"
    return 0
}

perform_inspection() {
    img_path="$1"
    block_mode="$2"
    inspector="$WORK_DIR/arb_inspector"

    if ! run_as_su "test -f \"$inspector\"" || ! run_as_su "test -x \"$inspector\""; then
        handle_error "arb_inspector tool not found or not executable" 1 ""
    fi

    if ! check_file_exists "$img_path"; then
        handle_error "Image file $img_path does not exist" 2 ""
    fi

    cmd_base="$inspector"
    if [ $block_mode -eq 1 ]; then
        cmd_base="$cmd_base --block"
    fi

    echo "Calling arb_inspector to check (debug mode)..."
    debug_output=$(run_as_su "$cmd_base --debug \"$img_path\"" 2>&1)
    debug_status=$?
    if [ $debug_status -ne 0 ]; then
        echo "Warning: arb_inspector debug mode execution failed, exit code $debug_status" >&2
        echo "$debug_output" >&2
    else
        echo ""
        echo "========== Debug Output =========="
        echo "$debug_output"
        echo "=================================="
    fi

    echo ""
    echo "Calling arb_inspector to check (normal mode)..."
    normal_output=$(run_as_su "$cmd_base \"$img_path\"" 2>&1)
    normal_status=$?
    if [ $normal_status -ne 0 ]; then
        handle_error "arb_inspector normal mode execution failed" $normal_status "$normal_output"
    fi

    echo ""
    echo "========== Normal Inspection Result =========="
    echo "$normal_output"
    echo "=============================================="

    arb_version=$(echo "$normal_output" | awk -F': ' '/Anti-Rollback Version/ {print $2}')
    if [ -z "$arb_version" ]; then
        echo "Warning: Could not parse Anti-Rollback Version from output" >&2
    else
        echo ""
        if [ "$arb_version" -eq 0 ] 2>/dev/null; then
            printf "\033[32mCurrent device anti-rollback value is 0\033[0m\n"
        elif [ "$arb_version" -gt 0 ] 2>/dev/null; then
            printf "\033[31mCurrent device has anti-rollback enabled, version: %s\033[0m\n" "$arb_version"
        else
            echo "Warning: Parsed version is not a number: $arb_version" >&2
        fi
    fi

    if [ $IS_MEDIATEK -eq 1 ]; then
        echo ""
        printf "\033[33mWarning: ARB on MediaTek Dimensity devices may be stored in hardware, the value read by this tool might be unreliable.\033[0m\n"
    fi

    return 0
}

process_partition() {
    path="$1"
    mode="$2"
    if [ "$mode" -eq 1 ]; then
        ensure_temp_dir
        dst="$WORK_DIR/$OUTPUT_FILE"
        run_as_su "cat '$path' > '$dst'" || {
            echo "Error: Cannot copy partition file" >&2
            return 1
        }
        perform_inspection "$dst" 0
    else
        perform_inspection "$path" 1
    fi
}

do_manual_selection() {
    part_path=$(select_partition_manually)
    if [ -z "$part_path" ]; then
        return 1
    fi
    echo "Choose operation:" >&2
    echo "  1) Directly inspect this partition" >&2
    echo "  2) Extract and inspect" >&2
    printf "Please enter number 1 or 2: " >&2
    read mode_choice
    case "$mode_choice" in
        1) process_partition "$part_path" 0 ;;
        2) process_partition "$part_path" 1 ;;
        *) echo "Invalid choice" >&2; return 1 ;;
    esac
}

handle_external() {
    echo ""
    echo "Please enter the path to xbl_config.img (absolute or relative):"
    printf "Path: "
    read external_path
    if [ -z "$external_path" ]; then
        echo "Error: Path cannot be empty" >&2
        exit 1
    fi
    case "$external_path" in
        /*) ;;
        *) external_path="$(pwd)/$external_path" ;;
    esac
    perform_inspection "$external_path" 0
}

handle_local() {
    echo "Choose operation mode:" >&2
    echo "  1) Auto mode (auto-detect partition)" >&2
    echo "  2) Manually select partition" >&2
    printf "Please enter number 1 or 2: " >&2
    read local_mode
    case "$local_mode" in
        1)
            part_path=$(find_partition_path "xbl_config" "$ACTIVE_SLOT")
            if [ -n "$part_path" ]; then
                echo "Found partition: $part_path" >&2
                echo "Choose inspection method:" >&2
                echo "  1) Directly inspect this partition" >&2
                echo "  2) Extract and inspect" >&2
                printf "Please enter number 1 or 2: " >&2
                read inspect_mode
                case "$inspect_mode" in
                    1) process_partition "$part_path" 0 ;;
                    2) process_partition "$part_path" 1 ;;
                    *) echo "Invalid choice, exiting." >&2; exit 1 ;;
                esac
            else
                echo "Auto detection failed, enter manual selection? (y/n)" >&2
                read ans
                case "$ans" in
                    [yY]|[yY][eE][sS]) do_manual_selection ;;
                    *) echo "User cancelled operation." >&2; exit 0 ;;
                esac
            fi
            ;;
        2)
            do_manual_selection
            ;;
        *)
            echo "Invalid choice, exiting." >&2
            exit 1
            ;;
    esac
}

ask_source_type() {
    echo "========================================" >&2
    echo "          Select Source" >&2
    echo "========================================" >&2
    echo "" >&2
    echo "Please select the source of xbl_config firmware to check:" >&2
    echo "" >&2
    echo "  1) Local partition" >&2
    echo "  2) External file" >&2
    echo "" >&2
    printf "Please enter number 1 or 2: " >&2
    read ask_source_type_result
    echo "$ask_source_type_result"
}

init() {
    if ! checkShell; then
        echo "Error: Unsupported shell type ($(getAndroidShellType)), script requires mksh, ash or ksh environment" >&2
        exit 1
    fi

    if ! check_su_exists; then
        echo "Error: Script requires root permissions, but su command not found" >&2
        exit 1
    fi
    
    check_cpu_arch
    check_if_mediatek
    find_busybox

    echo ""
    echo "Note: If you have anti-brick modules installed, this script may not be able to read your device's ARB." >&2
    echo ""

    SOURCE_CHOICE=$(ask_source_type)

    prepare_tools

    ACTIVE_SLOT=$(get_active_slot)

    case "$SOURCE_CHOICE" in
        1)
            handle_local
            ;;
        2)
            handle_external
            ;;
        *)
            echo "Invalid choice, script exiting." >&2
            exit 1
            ;;
    esac
}

main() {
    clear_screen
    echo "========================================"
    echo "  xbl_config Firmware Inspector"
    echo "  Author: dere3046"
    echo "  License: MIT"
    echo "========================================"
    build_info=$(getprop ro.build.display.id 2>/dev/null)
    if [ -n "$build_info" ]; then
        echo "System build: $build_info"
    else
        echo "System build: Unknown"
    fi
    echo "This script only operates in directory: /data/local/tmp/checkarb"
    echo "Other system partitions and directories are only read, not modified."
    echo ""
    init
}
#####End

trap cleanup EXIT
main
exit 0
__ARCHIVE_FOLLOWS__
