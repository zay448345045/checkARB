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
PART_BASE="/dev/block/bootdevice/by-name/"
OUTPUT_FILE="xbl_config.img"
BIN_ZIP_HASH="81efe18f604f93f21941d198a0157873d74a656a947572ff0e3a027ad8904298"
MARKER="__ARCHIVE_FOLLOWS__"
IS_MEDIATEK=0
BUSYBOX_CMD="busybox"
#####End

#####Fun
remove_work_dir() {
    if command -v su >/dev/null 2>&1; then
        su -c "rm -rf \"$WORK_DIR\"" 2>/dev/null
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
    if [ -n "$mtk_platform" ] && echo "$mtk_platform" | grep -i 'mt' >/dev/null 2>&1; then
        IS_MEDIATEK=1
    elif [ -n "$board_platform" ] && echo "$board_platform" | grep -i '^mt' >/dev/null 2>&1; then
        IS_MEDIATEK=1
    elif [ -n "$chipname" ] && echo "$chipname" | grep -i 'dimensity' >/dev/null 2>&1; then
        IS_MEDIATEK=1
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
    get_active_slot_slot=$(getprop ro.boot.slot_suffix 2>/dev/null)
    if [ -z "$get_active_slot_slot" ]; then
        get_active_slot_slot=$(getprop ro.boot.slot 2>/dev/null)
        if [ -n "$get_active_slot_slot" ]; then
            case "$get_active_slot_slot" in
                a|b) get_active_slot_slot="_$get_active_slot_slot" ;;
                *) get_active_slot_slot="" ;;
            esac
        fi
    fi
    echo "$get_active_slot_slot"
}

prepare_tools() {
    echo "Preparing detection tools..."
    remove_work_dir
    su -c "mkdir -p \"$WORK_DIR\"" 2>/dev/null || {
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
    tail -n +$((line + 1)) "$script_self" | su -c "cat > \"$tmp_zip\"" 2>/dev/null || {
        echo "Error: Failed to extract appended data" >&2
        exit 1
    }

    if command -v sha256sum >/dev/null 2>&1; then
        computed_hash=$(su -c "sha256sum \"$tmp_zip\"" | cut -d' ' -f1)
    elif command -v $BUSYBOX_CMD >/dev/null 2>&1 && $BUSYBOX_CMD --list | grep sha256sum >/dev/null 2>&1; then
        computed_hash=$(su -c "$BUSYBOX_CMD sha256sum \"$tmp_zip\"" | cut -d' ' -f1)
    elif command -v openssl >/dev/null 2>&1; then
        computed_hash=$(su -c "openssl dgst -sha256 \"$tmp_zip\"" | cut -d' ' -f2)
    else
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
        su -c "unzip -q -o \"$tmp_zip\" -d \"$WORK_DIR\"" || {
            echo "Error: Failed to extract bin.zip" >&2
            exit 1
        }
    elif command -v $BUSYBOX_CMD >/dev/null 2>&1 && $BUSYBOX_CMD --list | grep unzip >/dev/null 2>&1; then
        su -c "$BUSYBOX_CMD unzip -q -o \"$tmp_zip\" -d \"$WORK_DIR\"" || {
            echo "Error: Failed to extract using $BUSYBOX_CMD" >&2
            exit 1
        }
    else
        echo "Error: unzip command not found, cannot extract tool package" >&2
        exit 1
    fi

    su -c "rm -f \"$tmp_zip\""

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

    if ! su -c "test -f \"$WORK_DIR/$tool_zip\""; then
        echo "Error: $tool_zip not found in bin.zip" >&2
        exit 1
    fi

    if command -v unzip >/dev/null 2>&1; then
        su -c "unzip -q -o \"$WORK_DIR/$tool_zip\" -d \"$WORK_DIR\"" || {
            echo "Error: Failed to extract $tool_zip" >&2
            exit 1
        }
    elif command -v $BUSYBOX_CMD >/dev/null 2>&1 && $BUSYBOX_CMD --list | grep unzip >/dev/null 2>&1; then
        su -c "$BUSYBOX_CMD unzip -q -o \"$WORK_DIR/$tool_zip\" -d \"$WORK_DIR\"" || {
            echo "Error: Failed to extract $tool_zip using $BUSYBOX_CMD" >&2
            exit 1
        }
    else
        echo "Error: unzip command not found, cannot extract $tool_zip" >&2
        exit 1
    fi

    su -c "rm -f \"$WORK_DIR\"/arb_inspector-*.zip"
    su -c "chmod 755 \"$WORK_DIR/arb_inspector\"" 2>/dev/null || {
        echo "Error: Cannot set executable permission for arb_inspector" >&2
        exit 1
    }

    echo "Tools preparation completed."
}

confirm_extraction() {
    confirm_extraction_slot="$1"
    echo "========================================"
    echo "          Extraction Confirmation"
    echo "========================================"
    echo ""
    echo "Active slot: ${confirm_extraction_slot:-none}"
    echo ""
    echo "Extract the corresponding xbl_config firmware?"
    echo ""
    printf "Please enter y to confirm, n to cancel: "
    read confirm_extraction_ans
    case "$confirm_extraction_ans" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_temp_dir() {
    su -c "mkdir -p \"$WORK_DIR\"" 2>/dev/null || {
        echo "Error: Cannot create directory $WORK_DIR" >&2
        exit 1
    }
}

fetch_xbl_config() {
    fetch_xbl_config_slot="$1"
    fetch_xbl_config_partition="xbl_config"
    if [ -n "$fetch_xbl_config_slot" ]; then
        fetch_xbl_config_partition="xbl_config${fetch_xbl_config_slot}"
    fi
    fetch_xbl_config_src="${PART_BASE}${fetch_xbl_config_partition}"
    fetch_xbl_config_dst="${WORK_DIR}/${OUTPUT_FILE}"

    if ! su -c "test -e '$fetch_xbl_config_src'"; then
        echo "Error: Partition $fetch_xbl_config_src does not exist" >&2
        return 1
    fi

    if ! su -c "cat '$fetch_xbl_config_src' > '$fetch_xbl_config_dst'"; then
        echo "Error: Cannot read partition $fetch_xbl_config_src or write to $fetch_xbl_config_dst" >&2
        return 1
    fi

    echo "Successfully copied $fetch_xbl_config_partition to $fetch_xbl_config_dst"
    return 0
}

ask_source_type() {
    echo "========================================" >&2
    echo "          Select Source" >&2
    echo "========================================" >&2
    echo "" >&2
    echo "Please select the source of xbl_config firmware to check:" >&2
    echo "" >&2
    echo "  1) Local partition (extract from current device)" >&2
    echo "  2) External file (manually provide img file)" >&2
    echo "" >&2
    printf "Please enter number 1 or 2: " >&2
    read ask_source_type_result
    echo "$ask_source_type_result"
}

inspect_generic() {
    img_path="$1"
    inspector="$WORK_DIR/arb_inspector"
    if ! su -c "test -f \"$inspector\"" || ! su -c "test -x \"$inspector\""; then
        echo "Error: arb_inspector tool not found or not executable" >&2
        exit 1
    fi

    if ! su -c "test -f \"$img_path\""; then
        echo "Error: Image file $img_path does not exist" >&2
        return 1
    fi

    echo "Calling arb_inspector to check..."
    output=$(su -c "$inspector \"$img_path\"" 2>&1)
    inspect_status=$?
    if [ $inspect_status -ne 0 ]; then
        echo "Warning: arb_inspector execution failed, exit code $inspect_status" >&2
        echo "$output" >&2
        return $inspect_status
    fi

    echo ""
    echo "========== Inspection Result =========="
    echo "$output"
    echo "======================================="

    arb_version=$(echo "$output" | awk -F': ' '/Anti-Rollback Version/ {print $2}')
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
    inspect_generic "$external_path"
}

handle_local() {
    if confirm_extraction "$ACTIVE_SLOT"; then
        ensure_temp_dir
        if ! fetch_xbl_config "$ACTIVE_SLOT"; then
            echo "Error: Cannot obtain xbl_config firmware" >&2
            exit 1
        fi
        inspect_generic "$WORK_DIR/$OUTPUT_FILE"
    else
        echo "User cancelled operation."
        exit 0
    fi
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

    SOURCE_CHOICE=$(ask_source_type)

    prepare_tools

    ACTIVE_SLOT=$(get_active_slot)

    case "$SOURCE_CHOICE" in
        1) handle_local ;;
        2) handle_external ;;
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
