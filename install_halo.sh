#!/usr/bin/env bash
#
# MIT License
#
# Copyright (c) 2026 鼠宝财
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
#
# ---------------------------------------------------------------------------
# install_halo.sh —— 一键部署 Halo 博客（社区版）
#
#
# 作者：鼠宝财（MIT License，详见同目录 LICENSE 文件）
# 完整用法：bash install_halo.sh --help
# ---------------------------------------------------------------------------
#
# 被 sh/dash 误调用时自动用 bash 重新执行（脚本用到了 pipefail/local 等 bash 特性）
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -Eeuo pipefail

# ---------------------------------------------------------------- 默认配置 ----
HALO_VERSION="${HALO_VERSION:-2.26.1}"                             # 社区版版本号
HALO_IMAGE_REPO="${HALO_IMAGE_REPO:-registry.fit2cloud.com/halo/halo}"  # 国内镜像源；也可用 halohub/halo
DB_TYPE="${DB_TYPE:-postgres}"                                     # postgres | mysql | h2
HALO_PORT="${HALO_PORT:-8090}"
HALO_DIR="${HALO_DIR:-/opt/halo}"
HALO_EXTERNAL_URL="${HALO_EXTERNAL_URL:-}"
DB_NAME="${DB_NAME:-halo}"
DB_USER="${DB_USER:-halo}"
DB_PASSWORD="${DB_PASSWORD:-}"
JVM_OPTS="${JVM_OPTS:--Xmx512m -Xms256m}"
DOCKER_MIRROR="${DOCKER_MIRROR:-}"        # 可选：Docker Hub 加速地址，如 https://docker.m.daocloud.io
FORCE=0
OPEN_FIREWALL=0

# ------------------------------------------------------------------- 日志 ----
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
else
  C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''
fi
info()  { printf '%s[信息]%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok()    { printf '%s[完成]%s %s\n' "$C_OK"   "$C_RESET" "$*"; }
warn()  { printf '%s[警告]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
err()   { printf '%s[错误]%s %s\n' "$C_ERR"  "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }
trap 'err "脚本在第 $LINENO 行执行失败，已中止。"' ERR

# --------------------------------------------------------------- 参数解析 ----
usage() {
  cat <<'EOF'

install_halo.sh —— 一键部署 Halo 博客（社区版）
MIT License · Copyright (c) 2026 鼠宝财

用法：
  bash install_halo.sh [选项]

选项：
  --postgres, --pg      使用 PostgreSQL（默认）
  --mysql               使用 MySQL 8.0
  --h2                  使用内置 H2 单容器（仅测试，不建议生产）
  --port <端口>         Halo 对外端口，默认 8090
  --dir <目录>          安装目录，默认 /opt/halo
  --version <版本号>    Halo 版本号，默认 2.26.1
  --image <镜像仓库>    镜像仓库，默认 registry.fit2cloud.com/halo/halo
  --url <外部地址>      外部访问地址，默认自动探测公网 IP
  --db-password <密码>  数据库密码，默认随机生成（仅限字母数字和 . _ @ % + = -）
  --jvm-opts <参数>     JVM 参数，默认 "-Xmx512m -Xms256m"
  --mirror <地址|none>  指定 Docker Hub 加速地址；none 表示不配置；
                        不填则自动探测可用加速源（国内服务器强烈建议保留自动探测）
  --open-firewall       自动放行 ufw / firewalld 的本机端口
  --force               配置已存在时覆盖（旧文件自动备份）
  -h, --help            显示本帮助

对应环境变量：
  HALO_VERSION HALO_IMAGE_REPO DB_TYPE HALO_PORT HALO_DIR
  HALO_EXTERNAL_URL DB_PASSWORD JVM_OPTS DOCKER_MIRROR

示例：
  bash install_halo.sh                                  # 默认安装
  bash install_halo.sh --mysql --port 8080
  bash install_halo.sh --url https://blog.example.com --open-firewall
  HALO_PORT=9000 bash install_halo.sh --h2

EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --h2)            DB_TYPE=h2 ;;
    --mysql)         DB_TYPE=mysql ;;
    --postgres|--pg) DB_TYPE=postgres ;;
    --port)          HALO_PORT="${2:?--port 需要一个端口号}"; shift ;;
    --dir)           HALO_DIR="${2:?--dir 需要一个路径}"; shift ;;
    --version)       HALO_VERSION="${2:?--version 需要一个版本号}"; shift ;;
    --image)         HALO_IMAGE_REPO="${2:?--image 需要一个镜像地址}"; shift ;;
    --url)           HALO_EXTERNAL_URL="${2:?--url 需要一个地址}"; shift ;;
    --db-password)   DB_PASSWORD="${2:?--db-password 需要一个密码}"; shift ;;
    --jvm-opts)      JVM_OPTS="${2:?--jvm-opts 需要参数}"; shift ;;
    --mirror)        DOCKER_MIRROR="${2:?--mirror 需要一个地址}"; shift ;;
    --open-firewall) OPEN_FIREWALL=1 ;;
    --force)         FORCE=1 ;;
    -h|--help)       usage ;;
    *)               die "未知参数：$1（用 --help 查看用法）" ;;
  esac
  shift
done

HALO_IMAGE="${HALO_IMAGE_REPO}:${HALO_VERSION}"

case "$DB_TYPE" in postgres|mysql|h2) ;; *) die "DB_TYPE 只能是 postgres / mysql / h2，当前为：$DB_TYPE" ;; esac
case "$HALO_PORT" in ''|*[!0-9]*) die "端口号必须是数字：$HALO_PORT" ;; esac

# ------------------------------------------------------------- 前置环境检查 --
[ "$(id -u)" -eq 0 ] || die "请用 root 运行（或 sudo bash $0）"
[ -r /etc/os-release ] || die "无法读取 /etc/os-release，不支持的系统"
# shellcheck disable=SC1091
. /etc/os-release
OS_ID="${ID:-unknown}"; OS_VER="${VERSION_ID:-}"
ARCH="$(uname -m)"

info "系统：${PRETTY_NAME:-$OS_ID $OS_VER}（$ARCH）"
info "目标：Halo $HALO_VERSION，数据库 $DB_TYPE，端口 $HALO_PORT，目录 $HALO_DIR"

MEM_MB=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$MEM_MB" -gt 0 ] && [ "$MEM_MB" -lt 900 ] && [ "$DB_TYPE" != "h2" ]; then
  warn "内存仅 ${MEM_MB}MB，跑 Halo + 独立数据库可能吃紧，建议加内存或改用 --h2（不推荐生产）。"
fi

# ------------------------------------------------------------ Docker 检测 ----
docker_ready() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }

install_docker_official() {
  info "尝试使用 Docker 官方脚本安装（get.docker.com）……"
  local tmp; tmp="$(mktemp /tmp/get-docker.XXXXXX.sh)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 15 --max-time 120 https://get.docker.com -o "$tmp" || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 15 -O "$tmp" https://get.docker.com || return 1
  else
    warn "系统里没有 curl 也没有 wget，跳过官方脚本。"
    return 1
  fi
  sh "$tmp" || return 1
  rm -f "$tmp"
  command -v docker >/dev/null 2>&1
}

install_docker_distro() {
  warn "回退到发行版自带仓库安装 Docker（版本可能偏旧）。"
  case "$OS_ID" in
    ubuntu|debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y docker.io ca-certificates curl
      # 尽量补上 compose v2；没有就退到 docker-compose v1
      apt-get install -y docker-compose-v2 2>/dev/null || apt-get install -y docker-compose 2>/dev/null || true
      ;;
    centos|rhel|rocky|almalinux|fedora|opencloudos|tencentcos)
      command -v dnf >/dev/null 2>&1 && PKG=dnf || PKG=yum
      $PKG install -y docker docker-compose-plugin ca-certificates curl || $PKG install -y docker docker-compose ca-certificates curl
      ;;
    *) die "不认识的发行版：$OS_ID，请手动安装 Docker 后重跑本脚本。" ;;
  esac
  command -v docker >/dev/null 2>&1
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    ok "已检测到 Docker：$(docker --version 2>/dev/null || echo '版本未知')"
  else
    info "未检测到 Docker，开始自动安装……"
    install_docker_official || install_docker_distro || die "Docker 安装失败，请手动安装后重跑。"
    ok "Docker 安装完成：$(docker --version)"
  fi

  # 守护进程没起来就拉起来
  if ! docker info >/dev/null 2>&1; then
    info "Docker 守护进程未运行，尝试启动……"
    if command -v systemctl >/dev/null 2>&1; then
      systemctl enable --now docker || true
      sleep 3
    elif command -v service >/dev/null 2>&1; then
      service docker start || true
      sleep 3
    fi
  fi
  docker_ready || die "Docker 已安装但守护进程不可用，请检查：systemctl status docker / journalctl -u docker -n 50"
  ok "Docker 守护进程运行正常。"
}

# ------------------------------------------------ Docker Hub 镜像加速 ----
# 国内服务器直连 Docker Hub 基本不通（registry-1.docker.io 超时），
# 而 postgres / mysql 这类基础镜像只存在于 Docker Hub，所以必须先配好加速源。
MIRROR_CANDIDATES="https://mirror.ccs.tencentyun.com https://docker.m.daocloud.io https://docker.1ms.run https://hub-mirror.c.163.com https://mirror.baidubce.com"

mirror_ok() {
  local code
  command -v curl >/dev/null 2>&1 || return 0    # 没有 curl 就不探测，直接信任
  code="$(curl -sS -m 6 -o /dev/null -w '%{http_code}' "$1/v2/" 2>/dev/null)"
  case "$code" in 200|401|403) return 0 ;; *) return 1 ;; esac
}

write_daemon_json() {   # $1 = 逗号分隔的镜像地址列表（已带引号）
  local f=/etc/docker/daemon.json
  mkdir -p /etc/docker
  [ -f "$f" ] && cp -a "$f" "$f.bak.$(date +%s)"
  cat > "$f" <<EOF
{
  "registry-mirrors": [$1]
}
EOF
  info "已写入 $f，重启 Docker 使其生效……"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart docker; sleep 3
  elif command -v service >/dev/null 2>&1; then
    service docker restart; sleep 3
  fi
  docker_ready || die "配置镜像加速后 Docker 无法启动，请检查 $f"
}

ensure_registry_mirror() {
  if [ "$DOCKER_MIRROR" = "none" ]; then
    info "按 --mirror none 跳过镜像加速配置。"
    return 0
  fi

  if [ -n "$DOCKER_MIRROR" ]; then
    info "使用指定的镜像加速：$DOCKER_MIRROR"
    write_daemon_json "\"$DOCKER_MIRROR\""
    ok "镜像加速已生效。"
    return 0
  fi

  if docker info 2>/dev/null | sed -n '/Registry Mirrors/,/^$/p' | grep -q 'http'; then
    ok "检测到已有的 registry 加速配置，保持不变。"
    return 0
  fi

  info "未配置镜像加速，探测可用的加速源……"
  local found='' u
  for u in $MIRROR_CANDIDATES; do
    if mirror_ok "$u"; then found="$found $u"; info "  可用：$u"; else info "  不可用：$u"; fi
  done
  found="${found# }"
  if [ -z "$found" ]; then
    warn "没有探测到可用的加速源。若拉取 docker.io 镜像失败，请用 --mirror <地址> 手动指定。"
    return 0
  fi
  local json=''
  for u in $found; do json="$json\"$u\","; done
  write_daemon_json "${json%,}"
  ok "镜像加速已配置：$found"
}

# ------------------------------------------------------- Docker Compose ----
COMPOSE=(); COMPOSE_V1=0
ensure_compose() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose); ok "已检测到 Docker Compose v2（docker compose）"; return 0
  fi
  info "未检测到 Compose v2，尝试安装 docker-compose-plugin……"
  case "$OS_ID" in
    ubuntu|debian) export DEBIAN_FRONTEND=noninteractive; apt-get install -y docker-compose-plugin 2>/dev/null || apt-get install -y docker-compose-v2 2>/dev/null || true ;;
    *) command -v dnf >/dev/null 2>&1 && dnf install -y docker-compose-plugin 2>/dev/null || true ;;
  esac
  if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose); ok "Compose v2 安装完成。"; return 0
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose); COMPOSE_V1=1
    warn "只找到旧版 docker-compose v1，将使用兼容写法（建议尽快升级到 v2）。"
    return 0
  fi
  die "缺少 Docker Compose，请安装 docker-compose-plugin 后重跑。"
}

# ------------------------------------------------------------ 生成配置 ----
gen_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
  fi
}

detect_external_url() {
  [ -n "$HALO_EXTERNAL_URL" ] && { printf '%s' "$HALO_EXTERNAL_URL"; return; }
  local ip=''
  for u in https://api.ipify.org https://ifconfig.me/ip https://ipinfo.io/ip; do
    if command -v curl >/dev/null 2>&1; then
      ip="$(curl -fsS --connect-timeout 5 --max-time 8 "$u" 2>/dev/null | tr -d '[:space:]')" || ip=''
    elif command -v wget >/dev/null 2>&1; then
      ip="$(wget -qO- -T 8 "$u" 2>/dev/null | tr -d '[:space:]')" || ip=''
    fi
    [ -n "$ip" ] && break
  done
  if ! printf '%s' "$ip" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
  fi
  [ -n "$ip" ] || ip="127.0.0.1"
  printf 'http://%s:%s' "$ip" "$HALO_PORT"
}

write_files() {
  mkdir -p "$HALO_DIR"
  local compose="$HALO_DIR/docker-compose.yaml"
  local envf="$HALO_DIR/.env"

  if [ -e "$compose" ] && [ "$FORCE" -ne 1 ]; then
    warn "$compose 已存在，未做任何修改。"
    warn "要继续部署请加 --force（旧文件会自动备份），或先手动处理该目录。"
    exit 0
  fi

  [ -n "$DB_PASSWORD" ] || DB_PASSWORD="$(gen_password)"
  if [ "$DB_TYPE" != "h2" ] && ! printf '%s' "$DB_PASSWORD" | grep -Eq '^[A-Za-z0-9._@%+=-]{8,}$'; then
    die "数据库密码只支持字母、数字和 . _ @ % + = -（至少 8 位），当前值含特殊字符会让 compose 解析出错。"
  fi

  if [ "$FORCE" -eq 1 ] && [ -e "$compose" ]; then
    cp -a "$compose" "$compose.bak.$(date +%Y%m%d%H%M%S)"
    [ -f "$envf" ] && cp -a "$envf" "$envf.bak.$(date +%Y%m%d%H%M%S)"
    info "已备份原有配置文件。"
  fi

  local ext_url; ext_url="$(detect_external_url)"

  # .env 与 compose 分离，避免密码等特殊字符被 shell/YAML 反复转义
  cat > "$envf" <<EOF
HALO_IMAGE=$HALO_IMAGE
HALO_PORT=$HALO_PORT
HALO_EXTERNAL_URL=$ext_url
JVM_OPTS=$JVM_OPTS
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
EOF
  chmod 600 "$envf"

  local ver_line=''
  [ "$COMPOSE_V1" -eq 1 ] && ver_line='version: "2.4"'

  case "$DB_TYPE" in
    h2)
      cat > "$compose" <<EOF
# 本文件由 install_halo.sh 生成 · MIT License · Copyright (c) 2026 鼠宝财
$ver_line
services:
  halo:
    image: \${HALO_IMAGE}
    container_name: halo
    restart: on-failure:3
    volumes:
      - ./halo2:/root/.halo2
    ports:
      - "\${HALO_PORT}:8090"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8090/actuator/health/readiness"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 60s
    environment:
      - JVM_OPTS=\${JVM_OPTS}
    command:
      - --halo.external-url=\${HALO_EXTERNAL_URL}
EOF
      ;;
    postgres)
      cat > "$compose" <<EOF
# 本文件由 install_halo.sh 生成 · MIT License · Copyright (c) 2026 鼠宝财
$ver_line
services:
  halo:
    image: \${HALO_IMAGE}
    container_name: halo
    restart: on-failure:3
    depends_on:
      halodb:
        condition: service_healthy
    networks:
      - halo_network
    volumes:
      - ./halo2:/root/.halo2
    ports:
      - "\${HALO_PORT}:8090"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8090/actuator/health/readiness"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 60s
    environment:
      - JVM_OPTS=\${JVM_OPTS}
    command:
      - --spring.r2dbc.url=r2dbc:pool:postgresql://halodb:5432/\${DB_NAME}
      - --spring.r2dbc.username=\${DB_USER}
      - --spring.r2dbc.password=\${DB_PASSWORD}
      - --spring.sql.init.platform=postgresql
      - --halo.external-url=\${HALO_EXTERNAL_URL}
  halodb:
    image: postgres:15.4
    container_name: halo-db
    restart: on-failure:3
    networks:
      - halo_network
    volumes:
      - ./db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "\${DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
    environment:
      - POSTGRES_DB=\${DB_NAME}
      - POSTGRES_USER=\${DB_USER}
      - POSTGRES_PASSWORD=\${DB_PASSWORD}
      - PGUSER=\${DB_USER}
networks:
  halo_network:
EOF
      ;;
    mysql)
      cat > "$compose" <<EOF
# 本文件由 install_halo.sh 生成 · MIT License · Copyright (c) 2026 鼠宝财
$ver_line
services:
  halo:
    image: \${HALO_IMAGE}
    container_name: halo
    restart: on-failure:3
    depends_on:
      halodb:
        condition: service_healthy
    networks:
      - halo_network
    volumes:
      - ./halo2:/root/.halo2
    ports:
      - "\${HALO_PORT}:8090"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8090/actuator/health/readiness"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 60s
    environment:
      - JVM_OPTS=\${JVM_OPTS}
    command:
      - --spring.r2dbc.url=r2dbc:pool:mysql://halodb:3306/\${DB_NAME}
      - --spring.r2dbc.username=\${DB_USER}
      - --spring.r2dbc.password=\${DB_PASSWORD}
      - --spring.sql.init.platform=mysql
      - --halo.external-url=\${HALO_EXTERNAL_URL}
  halodb:
    image: mysql:8.0
    container_name: halo-db
    restart: on-failure:3
    networks:
      - halo_network
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_general_ci
      - --explicit_defaults_for_timestamp=true
    volumes:
      - ./mysql:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-u", "root", "-p\${DB_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 40s
    environment:
      - MYSQL_ROOT_PASSWORD=\${DB_ROOT_PASSWORD}
      - MYSQL_DATABASE=\${DB_NAME}
      - MYSQL_USER=\${DB_USER}
      - MYSQL_PASSWORD=\${DB_PASSWORD}
networks:
  halo_network:
EOF
      # MySQL 的 root 密码单独生成
      if ! grep -q '^DB_ROOT_PASSWORD=' "$envf"; then
        printf 'DB_ROOT_PASSWORD=%s\n' "$(gen_password)" >> "$envf"
      fi
      ;;
  esac

  ok "已生成 $compose 与 $envf"
  info "外部访问地址：$ext_url"
}

# --------------------------------------------------------------- 部署 ----
port_in_use() {
  command -v ss >/dev/null 2>&1 || return 1
  ss -lntH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$HALO_PORT\$"
}

pull_image() {   # $1=镜像  $2=用途说明
  info "拉取$2：$1"
  if docker pull "$1"; then ok "已就绪：$1"; return 0; fi
  return 1
}

deploy() {
  cd "$HALO_DIR"
  if port_in_use; then
    warn "端口 $HALO_PORT 已被占用，请确认没有别的服务在用（可加 --port 换端口）。"
  fi

  ensure_registry_mirror

  local db_image=''
  case "$DB_TYPE" in
    postgres) db_image='postgres:15.4' ;;
    mysql)    db_image='mysql:8.0' ;;
  esac

  local pull_failed=0
  if [ -n "$db_image" ]; then
    pull_image "$db_image" "数据库镜像" || pull_failed=1
  fi

  if ! pull_image "$HALO_IMAGE" "Halo 镜像"; then
    # 换另一个官方源重试；只有真正拉到才把地址写回 .env，避免留下拉不动的配置
    local alt_repo
    case "$HALO_IMAGE_REPO" in
      halohub/halo) alt_repo='registry.fit2cloud.com/halo/halo' ;;
      *)            alt_repo='halohub/halo' ;;
    esac
    warn "Halo 镜像拉取失败，改用备用源 $alt_repo 重试……"
    if docker pull "${alt_repo}:${HALO_VERSION}"; then
      HALO_IMAGE_REPO="$alt_repo"
      HALO_IMAGE="${alt_repo}:${HALO_VERSION}"
      sed -i "s|^HALO_IMAGE=.*|HALO_IMAGE=${HALO_IMAGE}|" "$HALO_DIR/.env"
      ok "备用源可用，已把 .env 中的 HALO_IMAGE 更新为 $HALO_IMAGE"
    else
      warn "备用源同样拉取失败。"
      pull_failed=1
    fi
  fi

  if [ "$pull_failed" -ne 0 ]; then
    warn "有镜像未拉取成功，仍尝试启动（若本地已有缓存镜像，不影响使用）。"
  fi

  info "启动容器……"
  "${COMPOSE[@]}" up -d

  info "等待 Halo 健康检查通过（最多 5 分钟）……"
  local status='' i
  for i in $(seq 1 60); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' halo 2>/dev/null || echo 'missing')"
    case "$status" in
      healthy) ok "Halo 已就绪（healthy）。"; return 0 ;;
      exited|dead)  break ;;
    esac
    sleep 5
  done

  err "Halo 未在预期时间内就绪（当前状态：$status）。最近日志："
  "${COMPOSE[@]}" logs --tail=60 halo || true
  return 1
}

summary() {
  local ext_url; ext_url="$(grep '^HALO_EXTERNAL_URL=' "$HALO_DIR/.env" | cut -d= -f2- || echo "http://<服务器IP>:$HALO_PORT")"
  cat <<EOF

------------------------------ 部署完成 ------------------------------
  安装目录   : $HALO_DIR（数据在 $HALO_DIR/halo2，务必定期备份）
  数据库     : $DB_TYPE
  镜像       : $HALO_IMAGE
  后台地址   : $ext_url/console
  首页地址   : $ext_url
  数据库口令 : 见 $HALO_DIR/.env（权限 600，请妥善保管）

  常用命令（在 $HALO_DIR 下执行）：
    查看状态 : ${COMPOSE[*]} ps
    查看日志 : ${COMPOSE[*]} logs -f halo
    重启     : ${COMPOSE[*]} restart halo
    升级     : 修改 .env 里的 HALO_IMAGE 版本号后 ${COMPOSE[*]} up -d
    停止     : ${COMPOSE[*]} down

  首次访问 /console 会进入初始化页面，按提示创建管理员账号即可。
  如果浏览器打不开，请检查：云厂商安全组 / 防火墙是否放行 $HALO_PORT 端口。
---------------------------------------------------------------------
  install_halo.sh · MIT License · Copyright (c) 2026 鼠宝财
EOF
}

# --------------------------------------------------------------- 主流程 ----
main() {
  ensure_docker
  ensure_compose
  write_files

  if [ "$OPEN_FIREWALL" -eq 1 ]; then
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
      ufw allow "$HALO_PORT"/tcp && info "已放行 ufw 端口 $HALO_PORT"
    elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
      firewall-cmd --permanent --add-port="$HALO_PORT"/tcp && firewall-cmd --reload && info "已放行 firewalld 端口 $HALO_PORT"
    else
      info "未检测到启用中的 ufw/firewalld，跳过防火墙放行。"
    fi
  fi

  if deploy; then
    summary
  else
    die "部署未成功，请查看上面的日志；修正后可重跑本脚本（配置已生成，重启用 '${COMPOSE[*]} up -d'）。"
  fi
}

main "$@"
