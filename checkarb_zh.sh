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

AWK_CMD=""
CUT_CMD=""
SORT_CMD=""
FIND_CMD=""
HEAD_CMD=""
TAIL_CMD=""
READLINK_CMD=""
MKDIR_CMD=""
RM_CMD=""
CHMOD_CMD=""
MKNOD_CMD=""
CAT_CMD=""
SHA256SUM_CMD=""
UNZIP_CMD=""
TR_CMD=""
DD_CMD=""
SED_CMD=""
#####End

#####Fun
run_as_su() {
    if command -v su >/dev/null 2>&1; then
        su -c "$1"
    else
        printf "\033[31m错误：需要root权限但找不到su命令\033[0m\n" >&2
        exit 1
    fi
}

find_command() {
    cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd"
        return 0
    fi
    if command -v toybox >/dev/null 2>&1; then
        if toybox "$cmd" --help >/dev/null 2>&1; then
            echo "toybox $cmd"
            return 0
        fi
    fi
    if [ -n "$BUSYBOX_CMD" ] && [ -x "$BUSYBOX_CMD" ]; then
        if "$BUSYBOX_CMD" "$cmd" --help >/dev/null 2>&1; then
            echo "$BUSYBOX_CMD $cmd"
            return 0
        fi
    fi
    return 1
}

remove_work_dir() {
    if command -v su >/dev/null 2>&1; then
        run_as_su "$RM_CMD -rf \"$WORK_DIR\""
    else
        $RM_CMD -rf "$WORK_DIR" 2>/dev/null
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
    printf "\033[31m错误：$msg (返回码 $code)\033[0m\n" >&2
    if [ -n "$output" ]; then
        printf "\033[33m原始输出：\033[0m\n" >&2
        echo "$output" >&2
    fi
    build_version=$(getprop ro.build.display.id 2>/dev/null)
    printf "\033[36m设备 Build 版本: ${build_version:-未知}\033[0m\n" >&2
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
        tmp_readlink=$(find_command readlink)
        if [ -n "$tmp_readlink" ]; then
            getAndroidShellType_sh_target=$(run_as_su "$tmp_readlink \"/system/bin/sh\"" 2>/dev/null)
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
                    busybox_out=$(busybox 2>&1)
                    case "$busybox_out" in
                        *ash*) getAndroidShellType_detected="ash" ;;
                        *bash*) getAndroidShellType_detected="bash" ;;
                    esac
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
            printf "\033[31m当前环境是bash，脚本不支持bash 如果你使用MT或者其他终端软件那么请使用系统环境执行\033[0m\n" >&2
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
    CPU_ARCH=$(echo "$CPU_ARCH" | $TR_CMD '[:upper:]' '[:lower:]')
    case "$CPU_ARCH" in
        *arm*|*aarch64*)
            readonly CPU_ARCH
            printf "\033[32m检测到 ARM 架构: $CPU_ARCH\033[0m\n"
            ;;
        *)
            printf "\033[31m错误：不支持的 CPU 架构 ($CPU_ARCH)，本脚本仅支持 ARM32/ARM64 设备。\033[0m\n" >&2
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
        found=$( $FIND_CMD "$search_path" -type f -name "busybox" -exec test -x {} \; -print 2>/dev/null | $HEAD_CMD -n 1 )
        if [ -n "$found" ] && [ -x "$found" ]; then
            BUSYBOX_CMD="$found"
            printf "\033[36m找到备用 busybox: $BUSYBOX_CMD\033[0m\n" >&2
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
    if $FIND_CMD /dev/block -maxdepth 0 -iname "xbl_config" 2>/dev/null >/dev/null; then
        run_as_su "$FIND_CMD /dev/block -iname '*xbl_config*' 2>/dev/null > \"$tmp_file\""
    else
        run_as_su "$FIND_CMD /dev/block -name '*xbl_config*' -o -name '*XBL_CONFIG*' 2>/dev/null > \"$tmp_file\""
    fi
    if [ -s "$tmp_file" ]; then
        if [ -n "$SORT_CMD" ]; then
            $SORT_CMD -u "$tmp_file" -o "$tmp_file"
        fi
        cat "$tmp_file"
    fi
    $RM_CMD -f "$tmp_file"
}

select_partition_manually() {
    printf "\033[33m正在扫描所有包含 xbl_config 的分区...\033[0m\n" >&2
    part_list=$(gather_xbl_config_partitions)
    count=0
    for p in $part_list; do
        count=$((count + 1))
    done
    if [ $count -eq 0 ]; then
        printf "\033[31m错误：未找到任何 xbl_config 分区文件\033[0m\n" >&2
        return 1
    fi
    printf "\033[32m找到以下分区：\033[0m\n" >&2
    i=1
    for p in $part_list; do
        printf "  \033[36m%d) %s\033[0m\n" $i "$p" >&2
        i=$((i + 1))
    done
    printf "\033[33m请输入数字选择 (1-%d): \033[0m" $count >&2
    read choice
    case "$choice" in
        ''|*[!0-9]*)
            printf "\033[31m错误：输入无效\033[0m\n" >&2
            return 1
            ;;
        *)
            if [ $choice -lt 1 ] || [ $choice -gt $count ]; then
                printf "\033[31m错误：数字超出范围\033[0m\n" >&2
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
    dir_list=$(run_as_su "$FIND_CMD /dev/block -type d -name 'by-name' 2>/dev/null")
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

check_and_rebuild_device() {
    path="$1"
    if ! run_as_su "test -L \"$path\""; then
        return 0
    fi
    target=$(run_as_su "$READLINK_CMD \"$path\"")
    if [ -z "$target" ]; then
        printf "\033[33m警告：无法读取软链接 $path\033[0m\n" >&2
        return 1
    fi
    if run_as_su "test -e \"$target\""; then
        return 0
    fi
    printf "\033[33m检测到可能使用了防格机模块：$path 指向的目标 $target 不存在。\033[0m\n" >&2
    printf "\033[33m要进行检测，需要重建 $target 设备节点。此操作可能暂时影响系统，但完成后会恢复。\033[0m\n" >&2
    printf "\033[33m是否继续？(y/n): \033[0m" >&2
    read ans
    case "$ans" in
        [yY]|[yY][eE][sS]) ;;
        *) printf "\033[33m用户取消操作。\033[0m\n" >&2; return 1 ;;
    esac

    target_basename=$(basename "$target")
    dev_info=$(run_as_su "cat /proc/partitions" | $AWK_CMD -v name="$target_basename" '$4==name {print $1,$2}')
    if [ -z "$dev_info" ]; then
        printf "\033[31m错误：无法在 /proc/partitions 中找到 $target_basename 的设备信息\033[0m\n" >&2
        return 1
    fi
    major=$(echo $dev_info | $AWK_CMD '{print $1}')
    minor=$(echo $dev_info | $AWK_CMD '{print $2}')

    target_dir=$(dirname "$target")
    run_as_su "$MKDIR_CMD -p \"$target_dir\""
    run_as_su "$MKNOD_CMD \"$target\" b $major $minor" || {
        printf "\033[31m错误：无法创建设备节点 $target\033[0m\n" >&2
        return 1
    }
    run_as_su "$CHMOD_CMD 0600 \"$target\""
    echo "$target" > "$WORK_DIR/rebuilt_device.tmp"
    return 0
}

prepare_tools() {
    printf "\033[32m正在准备检测工具...\033[0m\n"
    remove_work_dir
    run_as_su "$MKDIR_CMD -p \"$WORK_DIR\"" || {
        printf "\033[31m错误：无法创建目录 $WORK_DIR\033[0m\n" >&2
        exit 1
    }

    script_self="$0"
    line=$( $AWK_CMD "/^${MARKER}$/{print NR; exit}" "$script_self")
    if [ -z "$line" ]; then
        printf "\033[31m错误：未找到归档标记，请确认脚本未被修改\033[0m\n" >&2
        exit 1
    fi

    tmp_zip="$WORK_DIR/bin.zip"
    
    printf "\033[36m尝试方法1: tail + cat\033[0m\n" >&2
    if run_as_su "$TAIL_CMD -n +$((line + 1)) \"$script_self\" > \"$tmp_zip\"" 2>/dev/null; then
        printf "\033[32m方法1成功\033[0m\n" >&2
    else
        
        printf "\033[33m方法1失败，尝试方法2: dd\033[0m\n" >&2
        total_lines=$(run_as_su "$CAT_CMD \"$script_self\" | $WC_CMD -l")
        skip_lines=$line
        if run_as_su "$DD_CMD if=\"$script_self\" of=\"$tmp_zip\" bs=1 skip=$skip_lines 2>/dev/null"; then
            printf "\033[32m方法2成功\033[0m\n" >&2
        else
            
            printf "\033[33m方法2失败，尝试方法3: sed\033[0m\n" >&2
            if run_as_su "$SED_CMD -n '1,${line}d' \"$script_self\" > \"$tmp_zip\"" 2>/dev/null; then
                printf "\033[32m方法3成功\033[0m\n" >&2
            else
                printf "\033[31m错误：所有提取方法均失败，无法提取附加数据\033[0m\n" >&2
                exit 1
            fi
        fi
    fi

    
    if [ -n "$SHA256SUM_CMD" ]; then
        computed_hash=$(run_as_su "$SHA256SUM_CMD \"$tmp_zip\"" | $CUT_CMD -d' ' -f1)
    elif command -v openssl >/dev/null 2>&1; then
        computed_hash=$(run_as_su "openssl dgst -sha256 \"$tmp_zip\"" | $CUT_CMD -d' ' -f2)
    else
        computed_hash=""
    fi

    if [ -z "$computed_hash" ]; then
        printf "\033[31m错误：找不到可用的 SHA256 计算工具（需要 sha256sum 或 openssl）\033[0m\n" >&2
        exit 1
    fi

    if [ "$computed_hash" != "$BIN_ZIP_HASH" ]; then
        printf "\033[31m错误：bin.zip 哈希校验失败\033[0m\n" >&2
        printf "\033[33m期望: $BIN_ZIP_HASH\033[0m\n" >&2
        printf "\033[33m实际: $computed_hash\033[0m\n" >&2
        exit 1
    fi
    printf "\033[32m哈希校验通过。\033[0m\n"

    if [ -n "$UNZIP_CMD" ]; then
        run_as_su "$UNZIP_CMD -q -o \"$tmp_zip\" -d \"$WORK_DIR\"" || {
            printf "\033[31m错误：解压 bin.zip 失败\033[0m\n" >&2
            exit 1
        }
    else
        printf "\033[31m错误：未找到 unzip 命令，无法解压工具包\033[0m\n" >&2
        exit 1
    fi

    run_as_su "$RM_CMD -f \"$tmp_zip\""

    case "$CPU_ARCH" in
        *aarch64*|*arm64*)
            tool_zip="arb_inspector-aarch64-linux-android.zip"
            ;;
        *armv7*|*armeabi*|*arm*)
            tool_zip="arb_inspector-armv7-linux-androideabi.zip"
            ;;
        *)
            printf "\033[31m错误：无法识别的 ARM 架构变体: $CPU_ARCH\033[0m\n" >&2
            exit 1
            ;;
    esac

    if ! run_as_su "test -f \"$WORK_DIR/$tool_zip\""; then
        printf "\033[31m错误：在 bin.zip 中未找到 $tool_zip\033[0m\n" >&2
        exit 1
    fi

    if [ -n "$UNZIP_CMD" ]; then
        run_as_su "$UNZIP_CMD -q -o \"$WORK_DIR/$tool_zip\" -d \"$WORK_DIR\"" || {
            printf "\033[31m错误：解压 $tool_zip 失败\033[0m\n" >&2
            exit 1
        }
    else
        printf "\033[31m错误：未找到 unzip 命令，无法解压 $tool_zip\033[0m\n" >&2
        exit 1
    fi

    run_as_su "$RM_CMD -f \"$WORK_DIR\"/arb_inspector-*.zip"
    run_as_su "$CHMOD_CMD 755 \"$WORK_DIR/arb_inspector\"" 2>/dev/null || {
        printf "\033[31m错误：无法设置 arb_inspector 执行权限\033[0m\n" >&2
        exit 1
    }

    printf "\033[32m工具准备完成。\033[0m\n"
}

ensure_temp_dir() {
    run_as_su "$MKDIR_CMD -p \"$WORK_DIR\"" 2>/dev/null || {
        printf "\033[31m错误：无法创建目录 $WORK_DIR\033[0m\n" >&2
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
        printf "\033[31m错误：找不到 $partition_basename 分区\033[0m\n" >&2
        return 1
    fi
    
    fetch_xbl_config_dst="${WORK_DIR}/${OUTPUT_FILE}"
    if ! run_as_su "$CAT_CMD '$partition_path' > '$fetch_xbl_config_dst'"; then
        printf "\033[31m错误：无法读取分区 $partition_path 或写入 $fetch_xbl_config_dst\033[0m\n" >&2
        return 1
    fi

    printf "\033[32m已成功将 $(basename $partition_path) 复制到 $fetch_xbl_config_dst\033[0m\n"
    return 0
}

perform_inspection() {
    img_path="$1"
    block_mode="$2"
    inspector="$WORK_DIR/arb_inspector"

    if ! run_as_su "test -f \"$inspector\"" || ! run_as_su "test -x \"$inspector\""; then
        handle_error "arb_inspector 工具不存在或不可执行" 1 ""
    fi

    if ! check_file_exists "$img_path"; then
        handle_error "镜像文件 $img_path 不存在" 2 ""
    fi

    cmd_base="$inspector"
    if [ $block_mode -eq 1 ]; then
        cmd_base="$cmd_base --block"
    fi

    printf "\033[36m正在调用 arb_inspector 进行检查（调试模式）...\033[0m\n"
    debug_output=$(run_as_su "$cmd_base --debug \"$img_path\"" 2>&1)
    debug_status=$?
    if [ $debug_status -ne 0 ]; then
        printf "\033[33m警告：arb_inspector 调试模式执行失败，返回码 $debug_status\033[0m\n" >&2
        echo "$debug_output" >&2
    else
        printf "\n\033[33m========== 调试输出 ==========\033[0m\n"
        echo "$debug_output"
        printf "\033[33m==============================\033[0m\n"
    fi

    printf "\n\033[36m正在调用 arb_inspector 进行检查（正常模式）...\033[0m\n"
    normal_output=$(run_as_su "$cmd_base \"$img_path\"" 2>&1)
    normal_status=$?
    if [ $normal_status -ne 0 ]; then
        handle_error "arb_inspector 正常模式执行失败" $normal_status "$normal_output"
    fi

    printf "\n\033[32m========== 正常检查结果 ==========\033[0m\n"
    echo "$normal_output"
    printf "\033[32m==================================\033[0m\n"

    arb_version=$(echo "$normal_output" | $AWK_CMD -F': ' '/Anti-Rollback Version/ {print $2}')
    if [ -z "$arb_version" ]; then
        printf "\033[33m警告：无法从输出中解析 Anti-Rollback Version\033[0m\n" >&2
    else
        echo ""
        if [ "$arb_version" -eq 0 ] 2>/dev/null; then
            printf "\033[32m当前设备防回滚值为 0\033[0m\n"
        elif [ "$arb_version" -gt 0 ] 2>/dev/null; then
            printf "\033[31m当前设备启用了防回滚，版本: %s\033[0m\n" "$arb_version"
        else
            printf "\033[33m警告：解析到的版本号非数字: $arb_version\033[0m\n" >&2
        fi
    fi

    if [ $IS_MEDIATEK -eq 1 ]; then
        printf "\n\033[33m警告：天玑设备的ARB可能是存储在硬件中的，此工具读取的值可能不可信。\033[0m\n"
    fi

    return 0
}

handle_partition_check() {
    path="$1"
    inspect_mode="$2"
    if ! check_and_rebuild_device "$path"; then
        printf "\033[31m错误：无法处理分区 $path\033[0m\n" >&2
        exit 1
    fi
    if [ "$inspect_mode" -eq 1 ]; then
        ensure_temp_dir
        dst="$WORK_DIR/$OUTPUT_FILE"
        run_as_su "$CAT_CMD '$path' > '$dst'" || {
            printf "\033[31m错误：无法复制分区文件\033[0m\n" >&2
            return 1
        }
        perform_inspection "$dst" 0
    else
        perform_inspection "$path" 1
    fi
    if [ -f "$WORK_DIR/rebuilt_device.tmp" ]; then
        rebuilt=$(cat "$WORK_DIR/rebuilt_device.tmp")
        run_as_su "$RM_CMD -f \"$rebuilt\""
        $RM_CMD -f "$WORK_DIR/rebuilt_device.tmp"
    fi
}

do_manual_selection() {
    part_path=$(select_partition_manually)
    if [ -z "$part_path" ]; then
        return 1
    fi
    printf "\033[36m请选择操作：\033[0m\n" >&2
    printf "  1) 直接检查此分区\n" >&2
    printf "  2) 提取后检查\n" >&2
    printf "\033[33m请输入数字 1 或 2: \033[0m" >&2
    read mode_choice
    case "$mode_choice" in
        1) handle_partition_check "$part_path" 0 ;;
        2) handle_partition_check "$part_path" 1 ;;
        *) printf "\033[31m无效选择\033[0m\n" >&2; return 1 ;;
    esac
}

handle_external() {
    echo ""
    printf "\033[36m请输入 xbl_config.img 的路径（支持绝对或相对路径）：\033[0m\n"
    printf "路径: "
    read external_path
    if [ -z "$external_path" ]; then
        printf "\033[31m错误：路径不能为空\033[0m\n" >&2
        exit 1
    fi
    case "$external_path" in
        /*) ;;
        *) external_path="$(pwd)/$external_path" ;;
    esac
    perform_inspection "$external_path" 0
}

handle_local() {
    printf "\033[36m请选择操作模式：\033[0m\n" >&2
    printf "  1) 自动模式（自动查找分区）\n" >&2
    printf "  2) 手动选择分区\n" >&2
    printf "\033[33m请输入数字 1 或 2: \033[0m" >&2
    read local_mode
    case "$local_mode" in
        1)
            part_path=$(find_partition_path "xbl_config" "$ACTIVE_SLOT")
            if [ -n "$part_path" ]; then
                printf "\033[32m找到分区：$part_path\033[0m\n" >&2
                printf "\033[36m请选择检查方式：\033[0m\n" >&2
                printf "  1) 直接检查此分区\n" >&2
                printf "  2) 提取后检查\n" >&2
                printf "\033[33m请输入数字 1 或 2: \033[0m" >&2
                read inspect_mode
                case "$inspect_mode" in
                    1) handle_partition_check "$part_path" 0 ;;
                    2) handle_partition_check "$part_path" 1 ;;
                    *) printf "\033[31m无效选择，退出。\033[0m\n" >&2; exit 1 ;;
                esac
            else
                
                printf "\033[33m自动查找（标准路径）失败，尝试全局扫描...\033[0m\n" >&2
                all_parts=$(gather_xbl_config_partitions)
                matched=""
                for p in $all_parts; do
                    filename=$(basename "$p")
                    suffix=${filename##xbl_config}
                    if [ "$ACTIVE_SLOT" = "a" ] && { [ "$suffix" = "_a" ] || [ "$suffix" = "a" ]; }; then
                        matched="$p"
                        break
                    fi
                    if [ "$ACTIVE_SLOT" = "b" ] && { [ "$suffix" = "_b" ] || [ "$suffix" = "b" ]; }; then
                        matched="$p"
                        break
                    fi
                    if [ -z "$ACTIVE_SLOT" ] && [ -z "$suffix" ]; then
                        matched="$p"
                        break
                    fi
                done
                if [ -n "$matched" ]; then
                    printf "\033[32m全局扫描找到匹配分区：$matched\033[0m\n" >&2
                    printf "\033[36m请选择检查方式：\033[0m\n" >&2
                    printf "  1) 直接检查此分区\n" >&2
                    printf "  2) 提取后检查\n" >&2
                    printf "\033[33m请输入数字 1 或 2: \033[0m" >&2
                    read inspect_mode
                    case "$inspect_mode" in
                        1) handle_partition_check "$matched" 0 ;;
                        2) handle_partition_check "$matched" 1 ;;
                        *) printf "\033[31m无效选择，退出。\033[0m\n" >&2; exit 1 ;;
                    esac
                else
                    printf "\033[33m自动查找失败，是否进入手动选择？(y/n): \033[0m" >&2
                    read ans
                    case "$ans" in
                        [yY]|[yY][eE][sS]) do_manual_selection ;;
                        *) printf "\033[33m用户取消操作。\033[0m\n" >&2; exit 0 ;;
                    esac
                fi
            fi
            ;;
        2)
            do_manual_selection
            ;;
        *)
            printf "\033[31m无效选择，退出。\033[0m\n" >&2
            exit 1
            ;;
    esac
}

ask_source_type() {
    printf "\033[34m========================================\033[0m\n" >&2
    printf "\033[34m          选择来源\033[0m\n" >&2
    printf "\033[34m========================================\033[0m\n" >&2
    echo "" >&2
    printf "\033[36m请选择要检查的 xbl_config 固件来源：\033[0m\n" >&2
    echo "" >&2
    printf "  1) 本机分区\n" >&2
    printf "  2) 外部文件\n" >&2
    echo "" >&2
    printf "\033[33m请输入数字 1 或 2：\033[0m" >&2
    read ask_source_type_result
    echo "$ask_source_type_result"
}

init() {
    if ! checkShell; then
        exit 1
    fi

    if ! check_su_exists; then
        printf "\033[31m错误：脚本需要 root 权限，但系统中未找到 su 命令\033[0m\n" >&2
        exit 1
    fi
    
    AWK_CMD=$(find_command awk)
    CUT_CMD=$(find_command cut)
    SORT_CMD=$(find_command sort)
    FIND_CMD=$(find_command find)
    HEAD_CMD=$(find_command head)
    TAIL_CMD=$(find_command tail)
    READLINK_CMD=$(find_command readlink)
    MKDIR_CMD=$(find_command mkdir)
    RM_CMD=$(find_command rm)
    CHMOD_CMD=$(find_command chmod)
    MKNOD_CMD=$(find_command mknod)
    CAT_CMD=$(find_command cat)
    SHA256SUM_CMD=$(find_command sha256sum)
    UNZIP_CMD=$(find_command unzip)
    TR_CMD=$(find_command tr)
    DD_CMD=$(find_command dd)
    SED_CMD=$(find_command sed)
    WC_CMD=$(find_command wc)

    for cmd_var in AWK_CMD CUT_CMD FIND_CMD HEAD_CMD TAIL_CMD READLINK_CMD MKDIR_CMD RM_CMD CHMOD_CMD CAT_CMD TR_CMD DD_CMD SED_CMD WC_CMD; do
        eval "cmd_val=\$$cmd_var"
        if [ -z "$cmd_val" ]; then
            printf "\033[31m错误：找不到必要命令 ${cmd_var%_CMD}\033[0m\n" >&2
            exit 1
        fi
    done

    check_cpu_arch
    check_if_mediatek
    find_busybox

    if [ -n "$BUSYBOX_CMD" ] && [ -x "$BUSYBOX_CMD" ]; then
        AWK_CMD=$(find_command awk)
        CUT_CMD=$(find_command cut)
        SORT_CMD=$(find_command sort)
        FIND_CMD=$(find_command find)
        HEAD_CMD=$(find_command head)
        TAIL_CMD=$(find_command tail)
        READLINK_CMD=$(find_command readlink)
        MKDIR_CMD=$(find_command mkdir)
        RM_CMD=$(find_command rm)
        CHMOD_CMD=$(find_command chmod)
        MKNOD_CMD=$(find_command mknod)
        CAT_CMD=$(find_command cat)
        SHA256SUM_CMD=$(find_command sha256sum)
        UNZIP_CMD=$(find_command unzip)
        TR_CMD=$(find_command tr)
        DD_CMD=$(find_command dd)
        SED_CMD=$(find_command sed)
        WC_CMD=$(find_command wc)
    fi

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
            printf "\033[31m无效选择，脚本退出。\033[0m\n" >&2
            exit 1
            ;;
    esac
}

main() {
    clear_screen
    printf "\033[34m========================================\033[0m\n"
    printf "\033[34m  xbl_config 固件检测工具\033[0m\n"
    printf "\033[34m  作者: dere3046\033[0m\n"
    printf "\033[34m  许可证: MIT\033[0m\n"
    printf "\033[34m========================================\033[0m\n"
    build_info=$(getprop ro.build.display.id 2>/dev/null)
    if [ -n "$build_info" ]; then
        printf "\033[36m系统版本: $build_info\033[0m\n"
    else
        printf "\033[36m系统版本: 未知\033[0m\n"
    fi
    printf "\033[33m本脚本仅操作目录: /data/local/tmp/checkarb\033[0m\n"
    printf "\033[33m对其他系统分区和目录仅进行读取操作，不会修改。\033[0m\n"
    echo ""
    init
}
#####End

trap cleanup EXIT
main
exit 0
__ARCHIVE_FOLLOWS__
