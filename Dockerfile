# ─── setup-dev-env.sh 测试环境 ─────────────────────────────────────────────────
# 模拟 WSL2 Ubuntu 24.04 全新用户环境
#
# 构建:  docker build -t wsl-dev-test .
# 运行:  docker run -it --rm wsl-dev-test
# ───────────────────────────────────────────────────────────────────────────────

FROM ubuntu:24.04

ARG USERNAME=testuser
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

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
RUN groupadd --gid $USER_GID $USERNAME \
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
