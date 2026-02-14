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
BIN_ZIP_HASH="81efe18f604f93f21941d198a0157873d74a656a947572ff0e3a027ad8904298"
MARKER="__ARCHIVE_FOLLOWS__"
IS_MEDIATEK=0
BUSYBOX_CMD="busybox"
CANDIDATE_BASES="/dev/block/bootdevice/by-name /dev/block/platform/*/by-name /dev/block/by-name"
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
            echo "当前环境是bash，脚本不支持bash 如果你使用MT或者其他终端软件那么请使用系统环境执行" >&2
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
            echo "检测到 ARM 架构: $CPU_ARCH"
            ;;
        *)
            echo "错误：不支持的 CPU 架构 ($CPU_ARCH)，本脚本仅支持 ARM32/ARM64 设备。" >&2
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
            echo "找到备用 busybox: $BUSYBOX_CMD" >&2
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
        su -c "$find_cmd /dev/block -iname '*xbl_config*' 2>/dev/null > \"$tmp_file\""
    else
        su -c "find /dev/block -name '*xbl_config*' -o -name '*XBL_CONFIG*' 2>/dev/null > \"$tmp_file\""
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
    echo "正在扫描所有包含 xbl_config 的分区..." >&2
    part_list=$(gather_xbl_config_partitions)
    count=0
    for p in $part_list; do
        count=$((count + 1))
    done
    if [ $count -eq 0 ]; then
        echo "错误：未找到任何 xbl_config 分区文件" >&2
        return 1
    fi
    echo "找到以下分区：" >&2
    i=1
    for p in $part_list; do
        printf "  %d) %s\n" $i "$p" >&2
        i=$((i + 1))
    done
    printf "请输入数字选择 (1-%d): " $count >&2
    read choice
    case "$choice" in
        ''|*[!0-9]*)
            echo "错误：输入无效" >&2
            return 1
            ;;
        *)
            if [ $choice -lt 1 ] || [ $choice -gt $count ]; then
                echo "错误：数字超出范围" >&2
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
    dir_list=$(find /dev/block -type d -name "by-name" 2>/dev/null)
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
    echo "正在准备检测工具..."
    remove_work_dir
    su -c "mkdir -p \"$WORK_DIR\"" 2>/dev/null || {
        echo "错误：无法创建目录 $WORK_DIR" >&2
        exit 1
    }

    script_self="$0"
    line=$(awk "/^${MARKER}$/{print NR; exit}" "$script_self")
    if [ -z "$line" ]; then
        echo "错误：未找到归档标记，请确认脚本未被修改" >&2
        exit 1
    fi

    tmp_zip="$WORK_DIR/bin.zip"
    tail -n +$((line + 1)) "$script_self" | su -c "cat > \"$tmp_zip\"" 2>/dev/null || {
        echo "错误：提取附加数据失败" >&2
        exit 1
    }

    if command -v sha256sum >/dev/null 2>&1; then
        computed_hash=$(su -c "sha256sum \"$tmp_zip\"" | cut -d' ' -f1)
    elif command -v busybox >/dev/null 2>&1 && busybox sha256sum --help >/dev/null 2>&1; then
        computed_hash=$(su -c "busybox sha256sum \"$tmp_zip\"" | cut -d' ' -f1)
    elif [ -n "$BUSYBOX_CMD" ] && [ -x "$BUSYBOX_CMD" ] && "$BUSYBOX_CMD" sha256sum --help >/dev/null 2>&1; then
        computed_hash=$(su -c "$BUSYBOX_CMD sha256sum \"$tmp_zip\"" | cut -d' ' -f1)
    elif command -v openssl >/dev/null 2>&1; then
        computed_hash=$(su -c "openssl dgst -sha256 \"$tmp_zip\"" | cut -d' ' -f2)
    else
        computed_hash=""
    fi

    if [ -z "$computed_hash" ]; then
        echo "错误：找不到可用的 SHA256 计算工具（需要 sha256sum、busybox sha256sum 或 openssl）" >&2
        exit 1
    fi

    if [ "$computed_hash" != "$BIN_ZIP_HASH" ]; then
        echo "错误：bin.zip 哈希校验失败" >&2
        echo "期望: $BIN_ZIP_HASH" >&2
        echo "实际: $computed_hash" >&2
        exit 1
    fi
    echo "哈希校验通过。"

    if command -v unzip >/dev/null 2>&1; then
        su -c "unzip -q -o \"$tmp_zip\" -d \"$WORK_DIR\"" || {
            echo "错误：解压 bin.zip 失败" >&2
            exit 1
        }
    elif command -v busybox >/dev/null 2>&1 && busybox unzip --help >/dev/null 2>&1; then
        su -c "busybox unzip -q -o \"$tmp_zip\" -d \"$WORK_DIR\"" || {
            echo "错误：使用 busybox 解压失败" >&2
            exit 1
        }
    elif [ -n "$BUSYBOX_CMD" ] && [ -x "$BUSYBOX_CMD" ] && "$BUSYBOX_CMD" unzip --help >/dev/null 2>&1; then
        su -c "$BUSYBOX_CMD unzip -q -o \"$tmp_zip\" -d \"$WORK_DIR\"" || {
            echo "错误：使用备用 busybox 解压失败" >&2
            exit 1
        }
    else
        echo "错误：未找到 unzip 命令，无法解压工具包" >&2
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
            echo "错误：无法识别的 ARM 架构变体: $CPU_ARCH" >&2
            exit 1
            ;;
    esac

    if ! su -c "test -f \"$WORK_DIR/$tool_zip\""; then
        echo "错误：在 bin.zip 中未找到 $tool_zip" >&2
        exit 1
    fi

    if command -v unzip >/dev/null 2>&1; then
        su -c "unzip -q -o \"$WORK_DIR/$tool_zip\" -d \"$WORK_DIR\"" || {
            echo "错误：解压 $tool_zip 失败" >&2
            exit 1
        }
    elif command -v busybox >/dev/null 2>&1 && busybox unzip --help >/dev/null 2>&1; then
        su -c "busybox unzip -q -o \"$WORK_DIR/$tool_zip\" -d \"$WORK_DIR\"" || {
            echo "错误：使用 busybox 解压 $tool_zip 失败" >&2
            exit 1
        }
    elif [ -n "$BUSYBOX_CMD" ] && [ -x "$BUSYBOX_CMD" ] && "$BUSYBOX_CMD" unzip --help >/dev/null 2>&1; then
        su -c "$BUSYBOX_CMD unzip -q -o \"$WORK_DIR/$tool_zip\" -d \"$WORK_DIR\"" || {
            echo "错误：使用备用 busybox 解压 $tool_zip 失败" >&2
            exit 1
        }
    else
        echo "错误：未找到 unzip 命令，无法解压 $tool_zip" >&2
        exit 1
    fi

    su -c "rm -f \"$WORK_DIR\"/arb_inspector-*.zip"
    su -c "chmod 755 \"$WORK_DIR/arb_inspector\"" 2>/dev/null || {
        echo "错误：无法设置 arb_inspector 执行权限" >&2
        exit 1
    }

    echo "工具准备完成。"
}

confirm_extraction() {
    confirm_extraction_slot="$1"
    echo "========================================"
    echo "          提取确认"
    echo "========================================"
    echo ""
    echo "当前活动槽位: ${confirm_extraction_slot:-无}"
    echo ""
    echo "是否提取对应的 xbl_config 固件？"
    echo ""
    printf "请输入 y 确认，n 取消："
    read confirm_extraction_ans
    case "$confirm_extraction_ans" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_temp_dir() {
    su -c "mkdir -p \"$WORK_DIR\"" 2>/dev/null || {
        echo "错误：无法创建目录 $WORK_DIR" >&2
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
        echo "错误：找不到 $partition_basename 分区" >&2
        return 1
    fi
    
    fetch_xbl_config_dst="${WORK_DIR}/${OUTPUT_FILE}"
    
    if ! su -c "cat '$partition_path' > '$fetch_xbl_config_dst'"; then
        echo "错误：无法读取分区 $partition_path 或写入 $fetch_xbl_config_dst" >&2
        return 1
    fi

    echo "已成功将 $(basename $partition_path) 复制到 $fetch_xbl_config_dst"
    return 0
}

ask_source_type() {
    echo "========================================" >&2
    echo "          选择来源" >&2
    echo "========================================" >&2
    echo "" >&2
    echo "请选择要检查的 xbl_config 固件来源：" >&2
    echo "" >&2
    echo "  1) 本机分区 (从当前设备提取)" >&2
    echo "  2) 外部文件 (手动提供 img 文件)" >&2
    echo "  3) 更多 xbl_config (手动选择分区)" >&2
    echo "" >&2
    printf "请输入数字 1-3：" >&2
    read ask_source_type_result
    echo "$ask_source_type_result"
}

inspect_generic() {
    img_path="$1"
    inspector="$WORK_DIR/arb_inspector"
    if ! su -c "test -f \"$inspector\"" || ! su -c "test -x \"$inspector\""; then
        echo "错误：arb_inspector 工具不存在或不可执行" >&2
        exit 1
    fi

    if ! su -c "test -f \"$img_path\""; then
        echo "错误：镜像文件 $img_path 不存在" >&2
        return 1
    fi

    echo "正在调用 arb_inspector 进行检查..."
    output=$(su -c "$inspector \"$img_path\"" 2>&1)
    inspect_status=$?
    if [ $inspect_status -ne 0 ]; then
        echo "警告：arb_inspector 执行失败，返回码 $inspect_status" >&2
        echo "$output" >&2
        return $inspect_status
    fi

    echo ""
    echo "========== 检查结果 =========="
    echo "$output"
    echo "=============================="

    arb_version=$(echo "$output" | awk -F': ' '/Anti-Rollback Version/ {print $2}')
    if [ -z "$arb_version" ]; then
        echo "警告：无法从输出中解析 Anti-Rollback Version" >&2
    else
        echo ""
        if [ "$arb_version" -eq 0 ] 2>/dev/null; then
            printf "\033[32m当前设备防回滚值为 0\033[0m\n"
        elif [ "$arb_version" -gt 0 ] 2>/dev/null; then
            printf "\033[31m当前设备启用了防回滚，版本: %s\033[0m\n" "$arb_version"
        else
            echo "警告：解析到的版本号非数字: $arb_version" >&2
        fi
    fi

    if [ $IS_MEDIATEK -eq 1 ]; then
        echo ""
        printf "\033[33m警告：天玑设备的ARB可能是存储在硬件中的，此工具读取的值可能不可信。\033[0m\n"
    fi

    return 0
}

handle_external() {
    echo ""
    echo "请输入 xbl_config.img 的路径（支持绝对或相对路径）："
    printf "路径: "
    read external_path
    if [ -z "$external_path" ]; then
        echo "错误：路径不能为空" >&2
        exit 1
    fi
    case "$external_path" in
        /*) ;;
        *) external_path="$(pwd)/$external_path" ;;
    esac
    inspect_generic "$external_path"
}

handle_local_auto() {
    if confirm_extraction "$ACTIVE_SLOT"; then
        ensure_temp_dir
        if ! fetch_xbl_config "$ACTIVE_SLOT"; then
            echo "自动识别失败，是否进入手动选择？(y/n)" >&2
            read ans
            case "$ans" in
                [yY]|[yY][eE][sS])
                    manual_path=$(select_partition_manually)
                    if [ -n "$manual_path" ]; then
                        if fetch_xbl_config "" "$manual_path"; then
                            inspect_generic "$WORK_DIR/$OUTPUT_FILE"
                        else
                            exit 1
                        fi
                    else
                        exit 1
                    fi
                    ;;
                *)
                    echo "用户取消操作。" >&2
                    exit 0
                    ;;
            esac
        else
            inspect_generic "$WORK_DIR/$OUTPUT_FILE"
        fi
    else
        echo "用户取消操作。" >&2
        exit 0
    fi
}

handle_manual_select() {
    ensure_temp_dir
    manual_path=$(select_partition_manually)
    if [ -n "$manual_path" ]; then
        if fetch_xbl_config "" "$manual_path"; then
            inspect_generic "$WORK_DIR/$OUTPUT_FILE"
        else
            exit 1
        fi
    else
        exit 1
    fi
}

init() {
    if ! checkShell; then
        echo "错误：不支持的 Shell 类型（$(getAndroidShellType)），脚本需要 mksh、ash 或 ksh 环境" >&2
        exit 1
    fi

    if ! check_su_exists; then
        echo "错误：脚本需要 root 权限，但系统中未找到 su 命令" >&2
        exit 1
    fi
    
    check_cpu_arch
    check_if_mediatek
    find_busybox

    SOURCE_CHOICE=$(ask_source_type)

    prepare_tools

    ACTIVE_SLOT=$(get_active_slot)

    case "$SOURCE_CHOICE" in
        1) handle_local_auto ;;
        2) handle_external ;;
        3) handle_manual_select ;;
        *)
            echo "无效选择，脚本退出。" >&2
            exit 1
            ;;
    esac
}

main() {
    clear_screen
    echo "========================================"
    echo "  xbl_config 固件检测工具"
    echo "  作者: dere3046"
    echo "  许可证: MIT"
    echo "========================================"
    echo "本脚本仅操作目录: /data/local/tmp/checkarb"
    echo "对其他系统分区和目录仅进行读取操作，不会修改。"
    echo ""
    init
}
#####End

trap cleanup EXIT
main
exit 0
__ARCHIVE_FOLLOWS__
