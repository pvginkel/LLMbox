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
        libmagic1 \
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
    npx -y playwright@latest install --with-deps chromium && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/home/ubuntu/.npm-global/bin:${PATH}"

RUN su - ubuntu -c "npm config set prefix ~/.npm-global" && \
    su - ubuntu -c "npm update -g npm" && \
    su - ubuntu -c "npm install -g pnpm @anthropic-ai/claude-code @openai/codex"

RUN pipx install --global \
        mypy \
        poetry \
        pytest \
        ruff

COPY thunk.sh /usr/bin
