#!/usr/bin/env bash

set -euo pipefail

ZEROTIER_VERSION="1.16.0"
ZEROTIER_COMMIT="7b7d39becc4a775d33e8c0f673856fb91dea7f31"
ZEROTIER_REPO_URL="https://github.com/zerotier/ZeroTierOne.git"
ZEROTIER_SRC_ROOT="/mnt/sdcard/zerotier"
ZEROTIER_SRC_DIR="${ZEROTIER_SRC_ROOT}/src"

VENDOR_KERNEL_BRANCH="bl-v1.0.y"
VENDOR_KERNEL_REPO_URL="https://gitee.com/spacemit-buildroot/linux-6.1.git"
KERNEL_BUILD_ROOT="/mnt/sdcard/build_temp"
KERNEL_SRC_DIR="${KERNEL_BUILD_ROOT}/linux-6.1-bianbu"

BOOT_MOUNT="/mnt/bootpart"
BOOT_DEVICE=""
DEFAULT_BOOT_DEVICE="/dev/mmcblk2p4"
COPY_AUTH_TOKEN_TO_USER=""
JOIN_NETWORK_ID=""
ASSUME_YES=0
LANG_CHOICE=""

usage() {
    cat <<'EOF'
Usage:
  install_zerotier_one_riscv64_bpi_f3_opensuse_tumbleweed.sh [options]

Options:
  --yes                         Run non-interactively where possible.
  --lang en|ko                  Force installer language.
  --boot-device <device>        Override boot partition device.
  --copy-auth-token-to <user>   Copy ZeroTier auth token for a non-root user.
  --join-network <network-id>   Join a ZeroTier network after installation.
  --help                        Show this help.
EOF
}

say() {
    if [[ "${LANG_CHOICE}" == "ko" ]]; then
        printf '%s\n' "$2"
    else
        printf '%s\n' "$1"
    fi
}

die() {
    say "$1" "$2" >&2
    exit 1
}

confirm() {
    local prompt_en="$1"
    local prompt_ko="$2"
    if [[ "${ASSUME_YES}" -eq 1 ]]; then
        return 0
    fi
    local reply
    if [[ "${LANG_CHOICE}" == "ko" ]]; then
        read -r -p "${prompt_ko} [y/N]: " reply
    else
        read -r -p "${prompt_en} [y/N]: " reply
    fi
    [[ "${reply}" == "y" || "${reply}" == "Y" ]]
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1" "필수 명령이 없습니다: $1"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes)
                ASSUME_YES=1
                shift
                ;;
            --lang)
                [[ $# -ge 2 ]] || die "--lang requires a value" "--lang 옵션에는 값이 필요합니다"
                LANG_CHOICE="$2"
                shift 2
                ;;
            --boot-device)
                [[ $# -ge 2 ]] || die "--boot-device requires a value" "--boot-device 옵션에는 값이 필요합니다"
                BOOT_DEVICE="$2"
                shift 2
                ;;
            --copy-auth-token-to)
                [[ $# -ge 2 ]] || die "--copy-auth-token-to requires a value" "--copy-auth-token-to 옵션에는 값이 필요합니다"
                COPY_AUTH_TOKEN_TO_USER="$2"
                shift 2
                ;;
            --join-network)
                [[ $# -ge 2 ]] || die "--join-network requires a value" "--join-network 옵션에는 값이 필요합니다"
                JOIN_NETWORK_ID="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1" "알 수 없는 옵션입니다: $1"
                ;;
        esac
    done
}

select_language() {
    if [[ -n "${LANG_CHOICE}" ]]; then
        case "${LANG_CHOICE}" in
            en|ko) ;;
            *)
                die "Invalid language: ${LANG_CHOICE}" "잘못된 언어 값입니다: ${LANG_CHOICE}"
                ;;
        esac
        return
    fi

    if [[ "${ASSUME_YES}" -eq 1 ]]; then
        LANG_CHOICE="en"
        return
    fi

    clear || true
    printf '%s\n' "========================================================"
    printf '%s\n' " ZeroTier One ${ZEROTIER_VERSION} Installer for BPI-F3"
    printf '%s\n' "========================================================"
    read -r -p "Select language / 언어를 선택하세요 (1: English, 2: 한국어) [1/2]: " LANG_CHOICE
    if [[ "${LANG_CHOICE}" == "2" ]]; then
        LANG_CHOICE="ko"
    else
        LANG_CHOICE="en"
    fi
}

check_root() {
    [[ "${EUID}" -eq 0 ]] || die \
        "This script must be run as root." \
        "이 스크립트는 root 권한으로 실행해야 합니다."
}

check_platform() {
    need_cmd uname
    need_cmd zypper
    need_cmd git
    need_cmd make
    need_cmd perl
    need_cmd curl
    need_cmd modprobe
    need_cmd depmod
    need_cmd modinfo
    need_cmd systemctl

    local arch kernel_release
    arch="$(uname -m)"
    kernel_release="$(uname -r)"

    [[ -f /etc/os-release ]] || die \
        "/etc/os-release is missing." \
        "/etc/os-release 파일이 없습니다."
    # shellcheck disable=SC1091
    . /etc/os-release

    if [[ "${arch}" != "riscv64" ]]; then
        confirm \
            "This machine is ${arch}, not riscv64. Continue anyway?" \
            "현재 시스템 아키텍처는 ${arch}이며 riscv64가 아닙니다. 그래도 계속할까요?" || exit 1
    fi

    if [[ "${ID:-}" != "opensuse-tumbleweed" && "${PRETTY_NAME:-}" != *"openSUSE Tumbleweed"* ]]; then
        confirm \
            "This does not look like openSUSE Tumbleweed (${PRETTY_NAME:-unknown}). Continue anyway?" \
            "이 시스템은 openSUSE Tumbleweed로 보이지 않습니다 (${PRETTY_NAME:-알 수 없음}). 그래도 계속할까요?" || exit 1
    fi

    say \
        "Target kernel release: ${kernel_release}" \
        "대상 커널 릴리스: ${kernel_release}"
}

install_prereqs() {
    say \
        "[1/7] Installing required packages with zypper..." \
        "[1/7] zypper로 필요한 패키지를 설치합니다..."
    zypper --non-interactive install \
        git make gcc gcc-c++ flex bison dwarves perl curl kmod patch tar xz
}

prepare_zerotier_source() {
    say \
        "[2/7] Preparing ZeroTier source tree..." \
        "[2/7] ZeroTier 소스 트리를 준비합니다..."
    mkdir -p "${ZEROTIER_SRC_ROOT}"
    if [[ -d "${ZEROTIER_SRC_DIR}/.git" ]]; then
        git -C "${ZEROTIER_SRC_DIR}" fetch --tags origin
    else
        rm -rf "${ZEROTIER_SRC_DIR}"
        git clone "${ZEROTIER_REPO_URL}" "${ZEROTIER_SRC_DIR}"
    fi
    git -C "${ZEROTIER_SRC_DIR}" checkout --force "${ZEROTIER_COMMIT}"
    git -C "${ZEROTIER_SRC_DIR}" reset --hard "${ZEROTIER_COMMIT}"
    git -C "${ZEROTIER_SRC_DIR}" clean -fdx
}

build_install_zerotier() {
    say \
        "[3/7] Building and installing ZeroTier One ${ZEROTIER_VERSION}..." \
        "[3/7] ZeroTier One ${ZEROTIER_VERSION}을 빌드하고 설치합니다..."
    make -C "${ZEROTIER_SRC_DIR}" -j"$(nproc)"
    make -C "${ZEROTIER_SRC_DIR}" install
    install -D -m 0644 "${ZEROTIER_SRC_DIR}/debian/zerotier-one.service" /usr/lib/systemd/system/zerotier-one.service
    systemctl daemon-reload
    systemctl enable --now zerotier-one.service
}

mount_boot_partition() {
    local kernel_release config_path candidate mounted_here
    kernel_release="$(uname -r)"
    config_path="${BOOT_MOUNT}/config-${kernel_release}"
    mkdir -p "${BOOT_MOUNT}"

    if [[ -f "${config_path}" ]]; then
        return 0
    fi

    if mountpoint -q "${BOOT_MOUNT}"; then
        die \
            "Boot mount exists at ${BOOT_MOUNT} but config-${kernel_release} is missing." \
            "${BOOT_MOUNT}가 이미 마운트되어 있지만 config-${kernel_release} 파일이 없습니다."
    fi

    mounted_here=0
    for candidate in "${BOOT_DEVICE}" "${DEFAULT_BOOT_DEVICE}"; do
        [[ -n "${candidate}" ]] || continue
        [[ -b "${candidate}" ]] || continue
        mount "${candidate}" "${BOOT_MOUNT}"
        mounted_here=1
        break
    done

    [[ "${mounted_here}" -eq 1 ]] || die \
        "Could not mount the boot partition. Use --boot-device to specify it." \
        "부트 파티션을 마운트할 수 없습니다. --boot-device로 직접 지정하십시오."

    [[ -f "${config_path}" ]] || die \
        "Mounted ${BOOT_MOUNT}, but config-${kernel_release} was not found." \
        "${BOOT_MOUNT}를 마운트했지만 config-${kernel_release} 파일이 없습니다."
}

prepare_vendor_kernel_source() {
    say \
        "[4/7] Preparing vendor kernel source tree for TUN..." \
        "[4/7] TUN 빌드를 위한 vendor 커널 소스 트리를 준비합니다..."
    mkdir -p "${KERNEL_BUILD_ROOT}"
    if [[ ! -d "${KERNEL_SRC_DIR}/.git" ]]; then
        rm -rf "${KERNEL_SRC_DIR}"
        git clone --depth 1 --branch "${VENDOR_KERNEL_BRANCH}" "${VENDOR_KERNEL_REPO_URL}" "${KERNEL_SRC_DIR}"
    fi
}

build_install_tun_module() {
    local kernel_release config_path target_dir built_module vermagic
    kernel_release="$(uname -r)"
    config_path="${BOOT_MOUNT}/config-${kernel_release}"

    prepare_vendor_kernel_source

    say \
        "[5/7] Building tun.ko for ${kernel_release}..." \
        "[5/7] ${kernel_release}용 tun.ko를 빌드합니다..."

    git -C "${KERNEL_SRC_DIR}" clean -fdx
    cp "${config_path}" "${KERNEL_SRC_DIR}/.config"
    perl -0pi -e 's/CONFIG_LOCALVERSION=\"\"/CONFIG_LOCALVERSION=\"-legacy-k1\"/; s/# CONFIG_TUN is not set/CONFIG_TUN=m/; s/^CONFIG_TUN=y$/CONFIG_TUN=m/m' "${KERNEL_SRC_DIR}/.config"

    make -C "${KERNEL_SRC_DIR}" olddefconfig prepare modules_prepare
    make -C "${KERNEL_SRC_DIR}" -j1 drivers/net/tun.ko

    built_module="${KERNEL_SRC_DIR}/drivers/net/tun.ko"
    [[ -f "${built_module}" ]] || die \
        "tun.ko was not built successfully." \
        "tun.ko 빌드가 성공하지 않았습니다."

    vermagic="$(modinfo "${built_module}" | awk '/^vermagic:/ {print $2}')"
    [[ "${vermagic}" == "${kernel_release}" ]] || die \
        "tun.ko vermagic (${vermagic}) does not match the running kernel (${kernel_release})." \
        "tun.ko vermagic (${vermagic})가 실행 중인 커널 (${kernel_release})과 일치하지 않습니다."

    target_dir="/usr/lib/modules/${kernel_release}/kernel/drivers/net"
    mkdir -p "${target_dir}"
    install -m 0644 "${built_module}" "${target_dir}/tun.ko"
    depmod -a "${kernel_release}"
    printf '%s\n' 'tun' >/etc/modules-load.d/tun.conf
    modprobe tun
}

ensure_tun_support() {
    local kernel_release config_path
    kernel_release="$(uname -r)"

    if [[ -e /dev/net/tun ]]; then
        say \
            "[4/7] TUN is already available. Skipping module build." \
            "[4/7] TUN이 이미 사용 가능합니다. 모듈 빌드를 건너뜁니다."
        return 0
    fi

    mount_boot_partition
    config_path="${BOOT_MOUNT}/config-${kernel_release}"

    if grep -Eq '^CONFIG_TUN=(y|m)$' "${config_path}"; then
        say \
            "[4/7] Vendor config already enables TUN. Loading module..." \
            "[4/7] vendor 커널 설정에 이미 TUN이 있습니다. 모듈을 적재합니다..."
        printf '%s\n' 'tun' >/etc/modules-load.d/tun.conf
        modprobe tun || true
        [[ -e /dev/net/tun ]] && return 0
    fi

    build_install_tun_module
    [[ -e /dev/net/tun ]] || die \
        "TUN is still unavailable after installation." \
        "설치 후에도 TUN을 사용할 수 없습니다."
}

copy_auth_token_if_requested() {
    local user_name home_dir
    user_name="${COPY_AUTH_TOKEN_TO_USER}"

    if [[ -z "${user_name}" && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        if confirm \
            "Copy the ZeroTier auth token to ${SUDO_USER} for non-root zerotier-cli usage?" \
            "${SUDO_USER} 사용자가 비root로 zerotier-cli를 쓰도록 인증 토큰을 복사할까요?"; then
            user_name="${SUDO_USER}"
        fi
    fi

    [[ -n "${user_name}" ]] || return 0

    home_dir="$(getent passwd "${user_name}" | cut -d: -f6)"
    [[ -n "${home_dir}" && -d "${home_dir}" ]] || die \
        "Could not resolve home directory for user ${user_name}." \
        "사용자 ${user_name}의 홈 디렉터리를 확인할 수 없습니다."

    say \
        "[6/7] Copying auth token for ${user_name}..." \
        "[6/7] ${user_name}용 인증 토큰을 복사합니다..."
    cp /var/lib/zerotier-one/authtoken.secret "${home_dir}/.zeroTierOneAuthToken"
    chown "${user_name}:${user_name}" "${home_dir}/.zeroTierOneAuthToken"
    chmod 600 "${home_dir}/.zeroTierOneAuthToken"
}

join_network_if_requested() {
    [[ -n "${JOIN_NETWORK_ID}" ]] || return 0
    say \
        "[7/7] Joining ZeroTier network ${JOIN_NETWORK_ID}..." \
        "[7/7] ZeroTier 네트워크 ${JOIN_NETWORK_ID}에 가입합니다..."
    zerotier-cli join "${JOIN_NETWORK_ID}"
}

wait_for_zerotier_api() {
    local attempt max_attempts
    max_attempts=30

    say \
        "[7/7] Waiting for the local ZeroTier controller to become ready..." \
        "[7/7] 로컬 ZeroTier 컨트롤러가 준비될 때까지 기다립니다..."

    for attempt in $(seq 1 "${max_attempts}"); do
        if zerotier-cli info >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    die \
        "zerotier-cli could not reach the local controller after restart." \
        "재시작 후 zerotier-cli가 로컬 컨트롤러에 연결하지 못했습니다."
}

final_verify() {
    say \
        "Final verification:" \
        "최종 검증:"
    printf '\n'
    zerotier-one -v
    printf '\n'
    zerotier-cli info
    printf '\n'
    zerotier-cli listnetworks
    printf '\n'
    ip -brief address | grep '^zt' || true
    printf '\n'
    systemctl --no-pager --full status zerotier-one.service | sed -n '1,12p'
}

main() {
    parse_args "$@"
    select_language
    check_root

    say \
        "========================================================" \
        "========================================================"
    say \
        " ZeroTier One ${ZEROTIER_VERSION} Installer for BPI-F3" \
        " BPI-F3용 ZeroTier One ${ZEROTIER_VERSION} 설치기"
    say \
        " Pinned upstream commit: ${ZEROTIER_COMMIT}" \
        " 고정 업스트림 커밋: ${ZEROTIER_COMMIT}"
    say \
        "========================================================" \
        "========================================================"

    confirm \
        "Start the installation now?" \
        "지금 설치를 시작할까요?" || die \
        "Installation aborted." \
        "설치를 중단했습니다."

    check_platform
    install_prereqs
    prepare_zerotier_source
    build_install_zerotier
    ensure_tun_support

    say \
        "[6/7] Restarting ZeroTier and verifying service state..." \
        "[6/7] ZeroTier를 재시작하고 서비스 상태를 확인합니다..."
    systemctl restart zerotier-one.service
    systemctl is-active --quiet zerotier-one.service || die \
        "zerotier-one.service is not active after restart." \
        "재시작 후 zerotier-one.service가 active 상태가 아닙니다."
    wait_for_zerotier_api

    copy_auth_token_if_requested
    join_network_if_requested
    final_verify

    say \
        "Installation completed successfully." \
        "설치가 성공적으로 완료되었습니다."
}

main "$@"
