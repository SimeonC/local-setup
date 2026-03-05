FROM ubuntu:24.04

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

# Locale
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# System packages (including Ruby build deps)
RUN apt-get update -q && apt-get install -y -q --no-install-recommends \
    fish tmux jq build-essential unzip direnv curl wget ca-certificates \
    git sudo locales gpg gpg-agent sox openssh-client \
    libffi-dev libyaml-dev libssl-dev libreadline-dev zlib1g-dev autoconf \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Rename the existing ubuntu user (uid 1000) to dev, set fish as shell, grant sudo
RUN usermod -l $USERNAME -d /home/$USERNAME -m -s /usr/bin/fish ubuntu \
    && groupmod -n $USERNAME ubuntu \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# AWS CLI (aarch64)
RUN curl -fsSL 'https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip' -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Switch to dev user for user-local installs
USER $USERNAME
WORKDIR /home/$USERNAME

# Default npm packages installed when mise provisions Node
COPY configs/.default-npm-packages /home/$USERNAME/.default-npm-packages

# Mise — install with global tools pre-baked
RUN curl https://mise.run | sh \
    && mkdir -p /home/$USERNAME/.config/mise \
    && printf '[settings]\nidiomatic_version_file_enable_tools = ["node", "ruby"]\n\n[settings.ruby]\ncompile = false\n\n[tools]\nbun = "1.2.2"\nelixir = "1.18.1-otp-27"\nerlang = "27"\nnode = "24.11.0"\npython = "3.11.13"\nruby = "3.4.4"\n' \
       > /home/$USERNAME/.config/mise/config.toml \
    && /home/$USERNAME/.local/bin/mise trust -a \
    && /home/$USERNAME/.local/bin/mise install -y

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt-get update -q && sudo apt-get install -y -q gh \
    && sudo rm -rf /var/lib/apt/lists/*

# Grit
RUN curl -fsSL https://docs.grit.io/install | bash

# Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Pre-create fish config dir (host mounts overlay individual items at runtime)
RUN mkdir -p /home/$USERNAME/.config/fish

# Add GitHub SSH host keys to known_hosts
RUN mkdir -p /home/$USERNAME/.ssh \
    && ssh-keyscan github.com >> /home/$USERNAME/.ssh/known_hosts 2>/dev/null
