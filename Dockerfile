FROM ubuntu:rolling

RUN apt-get update -yqq && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        gnupg \
        inetutils-ping \
        iproute2 \
        libasound2t64 \
        libatk-bridge2.0-0t64 \
        libatk1.0-0t64 \
        libatspi2.0-0t64 \
        libgbm1 \
        libmagic1 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        lsof \
        net-tools \
        netcat-openbsd \
        pipx \
        postgresql-client \
        python3 \
        traceroute \
        unzip \
        vim \
        wget \
    && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/home/ubuntu/.npm-global/bin:${PATH}"

RUN su - ubuntu -c "npm config set prefix ~/.npm-global" && \
    su - ubuntu -c "npm install -g pnpm @anthropic-ai/claude-code"

RUN pipx install --global \
        mypy \
        poetry \
        pytest \
        ruff

COPY thunk.sh /usr/bin
