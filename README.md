# checkARB

[**English**](README.md) | [**中文**](README_zh.md)

---

## English

### Introduction
checkARB is a self-extracting shell script designed to extract and examine the anti-rollback version stored in the `xbl_config` partition of Android devices. It leverages a built-in `arb_inspector` tool to parse the partition image and displays the result with intuitive colored output. The script adheres to the POSIX standard and runs reliably on common Android shells such as `mksh` and `ash`.

### Features
- **Self‑Extracting**: A ZIP archive containing `arb_inspector` is appended to the script; it automatically unpacks to a temporary directory at runtime, eliminating the need for manual tool preparation.
- **Dual‑Source Inspection**: Choose to extract `xbl_config` directly from the **local partition** or examine a user‑supplied **external image file**.
- **Anti‑Rollback Detection**: Parses the `Anti-Rollback Version` via a dedicated tool. Values > 0 are highlighted in red (“Anti‑rollback enabled”), while 0 is shown in green (“No anti‑rollback”).
- **MediaTek Dimensity Warning**: Automatically detects MediaTek Dimensity chips and, if present, displays a yellow warning that the ARB value may be stored in hardware and potentially unreliable.
- **Fallback busybox**: Recursively searches `/data/adb` for an executable `busybox` to use when system commands are missing, improving compatibility across different environments.
- **POSIX‑Compliant**: Written in pure POSIX shell, it runs flawlessly on `mksh` and `ash`. It also detects `bash` and exits with an error message.
- **Clean‑up Guarantee**: Regardless of success or failure, the script uses a `trap` to automatically remove the working directory (`/data/local/tmp/checkarb`) on exit, leaving no residue.
- **Hash Verification**: The embedded `bin.zip` is validated against a SHA256 checksum to prevent tampering or corruption.
- **User‑Friendly Interface**: Plain‑text menus guide the user through source selection, extraction confirmation, and external path input—no extra tools like `dialog` are required.


[![Hits](https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https://github.com/Dere3046/checkARB&count_bg=%2379C83D&title_bg=%23555555&icon=github.svg&icon_color=%23E7E7E7&title=hits&edge_flat=false)](https://hits.seeyoufarm.com)

[![Total Downloads](https://img.shields.io/github/downloads/Dere3046/checkARB/total?style=for-the-badge&color=2ea44f&logo=github)](https://github.com/Dere3046/checkARB/releases)