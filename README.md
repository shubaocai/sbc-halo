# sbc-halo

> 鼠宝财 · 一键安装 Halo 博客（Docker）

一条命令在 Linux 服务器上把 [Halo](https://halo.run) 博客跑起来：自动检测并安装 Docker、自动配置国内镜像加速、生成 Docker Compose 配置、拉起服务并等健康检查通过。

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20systemd-blue)

---

## 目录

- [特性](#特性)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [使用示例](#使用示例)
- [参数说明](#参数说明)
- [环境变量](#环境变量)
- [默认值](#默认值)
- [执行流程](#执行流程)
- [部署后的目录结构](#部署后的目录结构)
- [常用运维命令](#常用运维命令)
- [常见问题](#常见问题)
- [卸载](#卸载)
- [参考文档](#参考文档)
- [License](#license)

---

## 特性

- **全自动**：服务器没装 Docker 就自动装（官方脚本失败会自动回退到发行版仓库）；缺 Docker Compose v2 也会补上。
- **国内友好**：自动探测可用的 Docker Hub 加速源，解决 `registry-1.docker.io` 超时导致基础镜像（postgres / mysql）拉不动的问题；Halo 镜像默认走国内源。
- **三种数据库**：PostgreSQL（默认，Halo 官方推荐）/ MySQL / H2（单容器，仅测试）。
- **幂等安全**：已存在的配置不会被覆盖；`--force` 会先把旧文件备份成 `.bak.时间戳`；数据库密码自动随机生成，只写在权限 `600` 的 `.env` 里。
- **拉取失败不会写坏配置**：切换镜像源时，只有备用源**真正拉取成功**才会把地址写回 `.env`。
- **部署即交付**：自动探测公网 IP 生成 `halo.external-url`、轮询健康检查、彩色中文日志、结束时打印后台地址和运维命令。
- **MIT 协议**，可自由修改分发。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 系统 | Linux（需 systemd），Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux / Fedora / OpenCloudOS / TencentOS |
| 权限 | **root**（或 `sudo`） |
| Shell | **bash**（不支持 `sh`/dash 直接运行，脚本会自动切换） |
| 内存 | 建议 ≥ 1GB；低于 900MB 且使用独立数据库时会告警 |
| 架构 | x86_64 / arm64 |
| 网络 | 能访问外网（装 Docker、拉镜像） |

已在 **Ubuntu 22.04.5 LTS（x86_64，腾讯云 CVM，2GB 内存）** 实测：从零开始自动装 Docker + 部署 Halo，约 2 分钟起服务，Halo 启动耗时约 17 秒。

## 快速开始

```bash
# 1. 克隆
git clone https://github.com/shubaocai/sbc-halo.git
cd sbc-halo

# 2. 执行（默认 PostgreSQL + Halo 2.26.1 + 8090 端口 + /opt/halo 目录）
sudo bash install_halo.sh
```

也可以不克隆仓库，把脚本下载到 `/tmp` 再执行（推荐这种写法：脚本先落盘，可以自己看一眼再跑，也避免 `curl | bash` 直接管道执行）：

```bash
curl -fsSL -o /tmp/halo.sh https://raw.githubusercontent.com/shubaocai/sbc-halo/main/install_halo.sh && sudo bash /tmp/halo.sh
```

> 如果 `raw.githubusercontent.com` 访问不稳定，可以换 jsDelivr 镜像（同一台腾讯云服务器实测两者均可达）：
>
> ```bash
> curl -fsSL -o /tmp/halo.sh https://cdn.jsdelivr.net/gh/shubaocai/sbc-halo@main/install_halo.sh && sudo bash /tmp/halo.sh
> ```

跑完后浏览器访问：

```
http://<服务器IP>:8090/console
```

首次访问会进入初始化页面，按提示创建管理员账号即可。

> **提示**：如果打算用域名访问，官方建议**先配好反向代理和域名解析再初始化**，否则后续改地址比较麻烦。可以在初始化时用 `--url https://blog.example.com` 指定外部地址。
>
> 打不开通常是**云厂商安全组**没放行端口，见[常见问题](#浏览器打不开)。

## 使用示例

```bash
# 默认安装：PostgreSQL + Halo 2.26.1，端口 8090，目录 /opt/halo
sudo bash install_halo.sh

# 用 MySQL 8.0，换 8080 端口
sudo bash install_halo.sh --mysql --port 8080

# 指定域名，并自动放行本机防火墙端口
sudo bash install_halo.sh --url https://blog.example.com --open-firewall

# 单容器 + 内置 H2 数据库（仅体验测试，别用于生产）
sudo bash install_halo.sh --h2

# 装指定版本，装到自定义目录
sudo bash install_halo.sh --version 2.26.0 --dir /data/halo

# 手动指定 Docker Hub 加速源（不填则自动探测）
sudo bash install_halo.sh --mirror https://docker.m.daocloud.io

# 已装过、想重装并覆盖配置（旧文件自动备份）
sudo bash install_halo.sh --force

# 查看帮助
bash install_halo.sh --help
```

## 参数说明

| 参数 | 说明 | 默认 |
| --- | --- | --- |
| `--postgres` / `--pg` | 使用 PostgreSQL | ✅ 默认 |
| `--mysql` | 使用 MySQL 8.0 | |
| `--h2` | 使用内置 H2 单容器（仅测试，不建议生产） | |
| `--port <端口>` | Halo 对外端口 | `8090` |
| `--dir <目录>` | 安装目录（配置与数据都放这里） | `/opt/halo` |
| `--version <版本号>` | Halo 社区版版本号 | `2.26.1` |
| `--image <镜像仓库>` | Halo 镜像仓库 | `registry.fit2cloud.com/halo/halo` |
| `--url <外部地址>` | `halo.external-url`，不填自动探测公网 IP | 自动探测 |
| `--db-password <密码>` | 数据库密码，字符仅限字母数字和 `. _ @ % + = -`（至少 8 位） | 随机生成 |
| `--jvm-opts <参数>` | JVM 参数 | `-Xmx512m -Xms256m` |
| `--mirror <地址\|none>` | Docker Hub 加速地址；`none` 表示不配置；不填则自动探测 | 自动探测 |
| `--open-firewall` | 自动放行 ufw / firewalld 的本机端口 | 关闭 |
| `--force` | 配置已存在时覆盖（旧文件自动备份） | 关闭 |
| `-h`, `--help` | 显示帮助 | |

## 环境变量

所有参数都可以用环境变量代替（参数优先级更高）：

```bash
HALO_PORT=9000 sudo -E bash install_halo.sh --h2
```

| 变量 | 对应参数 | 默认值 |
| --- | --- | --- |
| `HALO_VERSION` | `--version` | `2.26.1` |
| `HALO_IMAGE_REPO` | `--image` | `registry.fit2cloud.com/halo/halo` |
| `DB_TYPE` | `--postgres` / `--mysql` / `--h2` | `postgres` |
| `HALO_PORT` | `--port` | `8090` |
| `HALO_DIR` | `--dir` | `/opt/halo` |
| `HALO_EXTERNAL_URL` | `--url` | 自动探测 |
| `DB_PASSWORD` | `--db-password` | 随机生成 |
| `JVM_OPTS` | `--jvm-opts` | `-Xmx512m -Xms256m` |
| `DOCKER_MIRROR` | `--mirror` | 自动探测 |

> 用 `sudo` 传环境变量记得加 `-E`，否则变量会被 sudo 丢掉。

## 默认值

| 项目 | 默认值 |
| --- | --- |
| Halo 版本 | `2.26.1`（社区版） |
| Halo 镜像 | `registry.fit2cloud.com/halo/halo:2.26.1` |
| 数据库 | PostgreSQL `postgres:15.4` |
| 数据库名 / 用户 | `halo` / `halo` |
| 安装目录 | `/opt/halo` |
| 对外端口 | `8090` |
| JVM 参数 | `-Xmx512m -Xms256m` |

## 执行流程

1. **环境检查**：校验 root 权限、读取 `/etc/os-release`、检查内存，打印系统与目标信息。
2. **Docker 检测与安装**：`docker` 命令存在 **且** `docker info` 可用才算就绪；缺失时先试官方脚本 `get.docker.com`，失败则回退发行版仓库（apt：`docker.io` + `docker-compose-v2`；dnf：`docker` + `docker-compose-plugin`），最后 `systemctl enable --now docker` 并复核。
3. **Docker Compose 检测**：优先 `docker compose` v2；没有就尝试补装 `docker-compose-plugin`；只剩 v1 时自动改用 `version: "2.4"` 兼容写法。
4. **生成配置**：写入 `docker-compose.yaml` 与 `.env`（权限 `600`），自动探测公网 IP 生成 `halo.external-url`。
5. **镜像加速**：若未配置过 registry 加速，自动探测可用加速源并写入 `/etc/docker/daemon.json`，然后重启 Docker；**已有配置则保持不动**。
6. **拉取镜像**：按镜像逐个拉取，报错定位更清晰；Halo 镜像失败时换另一个官方源重试，**只有成功才写回 `.env`**。
7. **启动与等待**：`docker compose up -d`，轮询 `/actuator/health/readiness`（最多 5 分钟），成功后打印后台地址与运维命令；失败则自动输出最近 60 行日志。

## 部署后的目录结构

```
/opt/halo
├── docker-compose.yaml     # 容器编排（由脚本生成）
├── .env                    # 端口、镜像、数据库密码等，权限 600
├── halo2/                  # Halo 工作目录：文章、附件、主题、插件、密钥（务必备份）
└── db/                     # PostgreSQL 数据目录（--mysql 模式为 mysql/）
```

容器与网络：

| 名称 | 说明 |
| --- | --- |
| `halo` | Halo 应用容器，映射 `主机端口:8090` |
| `halo-db` | 数据库容器（`--h2` 模式无此容器） |
| `halo_halo_network` | 应用与数据库之间的内部网络 |

## 常用运维命令

在安装目录（默认 `/opt/halo`）下执行：

```bash
cd /opt/halo

docker compose ps                 # 查看状态
docker compose logs -f halo       # 实时看日志
docker compose restart halo       # 重启 Halo
docker compose down               # 停止并删除容器（数据保留）
docker compose up -d              # 启动

# 升级 Halo：改 .env 里的 HALO_IMAGE 版本号，然后
sed -i 's|^HALO_IMAGE=.*|HALO_IMAGE=registry.fit2cloud.com/halo/halo:2.26.2|' .env
docker compose pull && docker compose up -d

# 备份（数据都在这个目录，直接打包即可）
tar czf halo-backup-$(date +%F).tar.gz -C /opt/halo halo2 db .env
```

> Halo 2.8+ 内置了备份/恢复功能，也可以在后台「备份」页面一键备份。目录级备份与后台备份建议都做。

## 常见问题

### Docker Hub 拉取超时（`dial tcp ...: i/o timeout`）

国内服务器直连 `registry-1.docker.io` 基本不通，而 `postgres` / `mysql` 这类基础镜像只存在于 Docker Hub。脚本会**自动探测并配置镜像加速源**，正常情况下无需干预。

如果自动探测没找到可用源，可以手动指定：

```bash
sudo bash install_halo.sh --mirror https://docker.m.daocloud.io
```

内置候选源：`mirror.ccs.tencentyun.com`（腾讯云内网，最快）、`docker.m.daocloud.io`、`docker.1ms.run`、`hub-mirror.c.163.com`、`mirror.baidubce.com`。

> 加速源会经过第三方镜像站拉取 `docker.io` 镜像。Docker 有摘要（digest）校验，镜像内容不会被篡改，但拉取可用性依赖对方。已有加速配置时脚本不会改动它。

### 安装 Docker 时官方脚本失败

`get.docker.com` 在国内时通时不通（实测成功率约 1/3）。脚本会自动回退到发行版仓库安装（Ubuntu 下是 `docker.io` + `docker-compose-v2`），功能完全可用，只是 Docker 来源不同。想强制用官方源可自行配置 `download.docker.com` 的 apt 源后重跑。

### 浏览器打不开

按顺序排查：

1. **云厂商安全组**：去控制台把 `8090`（或你自定义的端口）加入入站规则——这是最常见的原因。
2. **本机防火墙**：加 `--open-firewall` 让脚本自动放行 ufw / firewalld；或手动 `ufw allow 8090/tcp`。
3. **服务是否健康**：`docker compose ps` 看 `halo` 是否为 `healthy`，`curl -I http://127.0.0.1:8090/console` 看本机是否正常。
4. **面板类软件**：如果装了宝塔等面板，面板自身也有防火墙配置，要一并放行。

### 提示"配置文件已存在，未做任何修改"

脚本默认幂等，不会覆盖已有配置。要重新生成就加 `--force`，旧的 `docker-compose.yaml` 和 `.env` 会被备份为 `.bak.时间戳`。

### 要不要用 H2 数据库？

不要用于生产。H2 是内嵌文件数据库，操作不当可能损坏数据文件。它只适合内存很小或纯体验场景。生产请用默认的 PostgreSQL。

### 数据库密码怎么看 / 忘了

都在安装目录的 `.env` 里（权限 600）：

```bash
grep DB_PASSWORD /opt/halo/.env
```

### 想换端口或域名

改 `.env` 里的 `HALO_PORT` / `HALO_EXTERNAL_URL`，然后 `docker compose up -d`。注意 `halo.external-url` 要和实际访问地址一致，否则后台生成的链接会不对。

## 卸载

```bash
# 1. 停止并删除 Halo（数据目录会一起删掉，请先备份）
cd /opt/halo && docker compose down --remove-orphans
rm -rf /opt/halo

# 2. 卸载 Docker 本体（Ubuntu/Debian）
sudo systemctl disable --now docker.socket docker.service containerd.service
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
sudo apt-get purge -y docker.io containerd docker-compose-v2
sudo apt-get autoremove --purge -y
sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker /etc/containerd
sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
sudo groupdel docker 2>/dev/null
```

CentOS / RHEL 系把 `apt-get` 换成 `dnf` 即可。

## 参考文档

- Halo 官方文档：<https://docs.halo.run>
- 使用 Docker Compose 部署（本脚本的主要依据）：<https://docs.halo.run/guide/install/docker-compose>
- 使用 Docker 部署（单容器 H2 模式，对应脚本的 `--h2`）：<https://docs.halo.run/guide/install/docker>
- 配置说明：<https://docs.halo.run/guide/install/config>
- Halo 镜像源：社区版 `registry.fit2cloud.com/halo/halo`、`halohub/halo`

## License

[MIT](LICENSE) © 2026 鼠宝财
