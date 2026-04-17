# ─── setup-dev-env.sh 测试环境 ─────────────────────────────────────────────────
# 模拟 WSL2 Ubuntu 24.04 全新用户环境
#
# 构建:  docker build -t wsl-dev-test .
# 运行（无代理）:  docker run -it --rm wsl-dev-test
# 运行（有代理）:  docker run -it --rm \
#                   -e http_proxy=http://host.docker.internal:10809 \
#                   -e https_proxy=http://host.docker.internal:10809 \
#                   wsl-dev-test
# ───────────────────────────────────────────────────────────────────────────────

FROM ubuntu:24.04

ARG USERNAME=testuser
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# 切换 apt 镜像源为中科大（加速国内下载）
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/ubuntu.sources \
    && sed -i 's|http://security.ubuntu.com|http://mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/ubuntu.sources

# 安装最小化系统依赖（模拟真实 WSL2 Ubuntu 出厂状态）
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    curl \
    wget \
    git \
    ca-certificates \
    locales \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# 创建测试用户（模拟 WSL2 用户配置）
# Ubuntu 24.04 基础镜像已包含 uid=1000 的 ubuntu 用户，需先移除
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# 复制脚本
COPY setup-dev-env.sh /home/$USERNAME/setup-dev-env.sh
RUN chown $USERNAME:$USERNAME /home/$USERNAME/setup-dev-env.sh \
    && chmod +x /home/$USERNAME/setup-dev-env.sh

USER $USERNAME
WORKDIR /home/$USERNAME

CMD ["/bin/bash"]
