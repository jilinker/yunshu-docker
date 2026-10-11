# 云枢 Docker

在 Ubuntu 24.04 ARM64 容器中运行云枢（Yunshu），通过浏览器完成登录，并使用 Dante SOCKS5 访问容器可达的网络。

- **客户端版本**：`2.3.10.47`，基于 insta360 ARM64 安装包。
- **镜像架构**：`linux/arm64`，已在 Apple Silicon + OrbStack 验证。
- **代理端口**：容器内固定为 `7171/TCP`。
- **图形界面**：easy-novnc + TigerVNC + flwm，无需安装完整桌面环境。

## 快速开始：直接使用镜像

直接拉取镜像即可运行，无需下载源码或准备 DEB。

### 1. 拉取镜像

```sh
docker pull --platform linux/arm64 \
  crpi-bqdmpalw8hu6it5q.cn-shenzhen.personal.cr.aliyuncs.com/jaelinker_public/yunshu-docker:2.3.10.47
```

提供 `2.3.10.47` 和 `latest` 标签。建议使用版本标签，方便保持部署版本一致。当前仅提供 ARM64 镜像。

### 2. 启动容器

```sh
docker run -d --name yunshu \
  --platform linux/arm64 \
  --device /dev/net/tun \
  --cap-add NET_ADMIN \
  --shm-size 256m \
  --restart unless-stopped \
  --stop-timeout 30 \
  -p 127.0.0.1:7171:7171 \
  -p 127.0.0.1:6080:6080 \
  -p 127.0.0.1:5901:5901 \
  -v yunshu-home:/home/yunshu \
  -v yunshu-state:/var/lib/yunshu \
  crpi-bqdmpalw8hu6it5q.cn-shenzhen.personal.cr.aliyuncs.com/jaelinker_public/yunshu-docker:2.3.10.47
```

| 入口 | 默认宿主机地址 | 用途 |
| --- | --- | --- |
| SOCKS5 | `127.0.0.1:7171` | TCP 代理 |
| 浏览器 GUI | `http://127.0.0.1:6080` | 登录和操作云枢 |
| VNC | `127.0.0.1:5901` | 使用原生 VNC 客户端连接，可按需省略映射 |

`-p` 的格式为 `宿主机地址:宿主机端口:容器端口`。例如 `-p 127.0.0.1:17171:7171` 将宿主机代理改为 `17171`，容器内部仍使用 `7171`。

### 3. 登录并接入内网

读取首次生成的 VNC 密码：

```sh
docker exec yunshu cat /home/yunshu/.vnc/initial-password
```

打开 [浏览器 GUI](http://127.0.0.1:6080)，输入 VNC 密码连接桌面，再在云枢客户端中登录账号并点击“立即接入”。客户端显示“成功连接内网”后，再测试企业目标。

VNC 密码只用于连接桌面，与云枢账号密码无关。首次密码保存在 HOME 卷中，重启后保持不变。也可以在 `docker run` 中传入 `VNC_PASSWORD`，或挂载密码文件并设置 `VNC_PASSWORD_FILE`；指定密码时不会保留 `initial-password` 文件。传统 VNC 认证只使用密码的前 8 个字符。

### 4. 验证代理

```sh
curl --noproxy '' \
  --socks5-hostname 127.0.0.1:7171 \
  --connect-timeout 10 --max-time 20 \
  --head https://your-internal-service/
```

将地址替换为实际目标。`--socks5-hostname` 将域名交给容器解析。

默认 SOCKS5 无认证，支持 TCP CONNECT。代理按容器现有路由转发，不附加业务白名单或断线阻断；未接入 VPN 时仍可能访问普通网络目标。当前不提供 UDP 或独立 HTTP 代理。

## 使用 Docker Compose

仓库内的 Compose 默认使用上述预构建镜像：

```sh
git clone git@github.com:jilinker/yunshu-docker.git
cd yunshu-docker
cp .env.example .env
docker compose pull
docker compose up -d --no-build
```

读取 VNC 密码：

```sh
docker compose exec -T yunshu cat /home/yunshu/.vnc/initial-password
```

`.env` 可配置以下变量：

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `YUNSHU_IMAGE` | 阿里云仓库的 `2.3.10.47` 镜像，完整地址见 `.env.example` | 选择镜像及标签 |
| `BIND_ADDRESS` | `127.0.0.1` | 宿主机发布地址 |
| `SOCKS_PORT` | `7171` | 宿主机 SOCKS5 端口 |
| `WEB_PORT` | `6080` | 宿主机浏览器 GUI 端口 |
| `VNC_PORT` | `5901` | 宿主机 VNC 端口 |
| `VNC_SIZE` | `1280x800` | 虚拟桌面分辨率 |
| `YUNSHU_DEB_SHA256` | 当前安装包校验值 | 仅用于本地构建 |

`docker run` 示例使用 `yunshu-home`、`yunshu-state` 卷；Compose 默认使用带项目名前缀的独立卷。切换启动方式时，应明确复用原卷，避免启动到新的客户端状态。

## 本地构建

准备 ARM64 Docker 环境，并将安装包放入 `installers/yunshu.deb`：

```sh
cp /path/to/insta360_yunshu_2.3.10.47_arm64_insta360.deb installers/yunshu.deb
YUNSHU_IMAGE=yunshu:2.3.10.47 docker compose build
YUNSHU_IMAGE=yunshu:2.3.10.47 docker compose up -d --no-build
```

当前安装包 SHA-256：

```text
2a1318ae2b4fa519645e864eb5aca608d158eff90b38b9040f02ea4f8e5a3025
```

DEB 不包含在 Git 仓库中。升级客户端时，需要审查安装脚本适配，并同步更新镜像标签和安装包校验值。

## 运行与状态保留

直接使用镜像时：

```sh
docker ps --filter name=yunshu
docker exec yunshu healthcheck.sh
docker exec yunshu python3 /usr/local/bin/verify-container.py
docker stop yunshu
docker start yunshu
```

Compose 对应命令为 `docker compose ps`、`docker compose exec -T yunshu ...`、`docker compose stop yunshu` 和 `docker compose start yunshu`。

| 卷内目录 | 保存内容 |
| --- | --- |
| `/home/yunshu` | GUI 用户 HOME、VNC 配置与初始密码 |
| `/var/lib/yunshu` | 机器标识及客户端 `config`、`db`、`logs`、`tmp` |

关闭浏览器不会停止云枢。常驻服务由 s6 管理，异常退出后等待 5 秒再启动；tini 负责信号和子进程回收。健康检查验证基础服务和容器内监听，不检测 VPN 接入状态或宿主机端口发布；Docker 的 `unhealthy` 状态不会自动触发重启。

本次实测重启后已登录账号保留，但需要在 GUI 再次点击“立即接入”。容器重建已验证机器标识、VNC 密码和基础配置保持一致；重建后的完整登录会话仍需验证。日常 `docker compose down` 会保留卷，`down -v` 会删除卷内状态。

保留云枢 updater 组件。客户端自更新的程序文件尚未验证能跨容器重建保留，升级建议更换 DEB 并重建镜像。

## 故障排查

### 宿主机连接 7171 被拒绝

先分别从容器内和宿主机测试 SOCKS5。若容器内成功、宿主机连接被拒绝，检查实际监听：

```sh
lsof -nP -iTCP:7171 -sTCP:LISTEN
```

`docker port` 列出映射不代表 OrbStack 已成功绑定端口。本次排查发现，端口冲突曾导致 OrbStack 创建转发失败；占用释放后，快速 `restart` 仍沿用失效记录。

先解决端口占用，然后分开停止和启动，确认旧监听已移除后再启动：

```sh
docker stop yunshu
# 确认旧端口监听已移除后执行：
docker start yunshu
```

Compose 使用 `docker compose stop yunshu` 和 `docker compose start yunshu`。客户端恢复后检查是否需要重新接入内网。

### 接入内网后，直连成功但代理仍超时

确认 GUI 已显示成功接入。若容器直连目标成功、Dante 请求仍失败，可仅重启代理后复测：

```sh
docker exec yunshu s6-svc -r /run/service/dante
```

Compose 使用 `docker compose exec -T yunshu s6-svc -r /run/service/dante`。本次这样恢复了接入前解析到 Clash Fake-IP 的域名请求；该命令不会重启云枢客户端。

## 实现与验证

Dante 与云枢运行在同一个容器中，使用 `external.rotation: route` 按当前路由选择出口。启动时读取实际接口，每 5 秒检查接口地址变化并重载配置。浏览器入口由 easy-novnc 提供，桌面使用 TigerVNC 和 flwm。

构建时完成官方 `dpkg` 初始化，暂时延迟已审查的服务控制操作，完成后恢复原脚本。补入安装脚本缺失的 `PROCESS_NAME=yunshu`，并为截图组件提供带 `LIBJPEGTURBO_6.2` ABI 的 Debian bookworm ARM64 兼容库，保留其版本与版权记录。

GUI 使用厂商服务已有的 `--disable-http2 --no-sandbox` 参数：实测 Docker 默认权限阻止 Chromium 创建沙箱 namespace。运行依赖包含系统和用户 D-Bus、AT-SPI、中文字体及必要动态库。

已验证 GUI、常驻服务、SOCKS5 转发、停止重启和状态保留。登录并接入内网后，容器直连、宿主机 SOCKS5 和当前 Clash TUN 环境下访问 JumpServer 入口均返回 HTTP 200；浏览器认证流程未完成验证。

项目负责客户端容器化和代理入口，宿主机路由、Clash 分流及额外网络策略由使用方配置。

- [实施方案与技术记录](IMPLEMENTATION_PLAN.md)
- [实际验证记录](docs/verification.md)
- 参考实现：[Hagb/docker-easyconnect](https://github.com/Hagb/docker-easyconnect)
