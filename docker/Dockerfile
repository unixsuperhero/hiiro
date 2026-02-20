# Hiiro Docker Testing Environment
FROM ruby:3.2-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    tmux \
    fzf \
    curl \
    build-essential \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Install skim (sk) - fuzzy finder
# Use architecture detection for proper binary
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        curl -sL https://github.com/lotabout/skim/releases/download/v0.10.4/skim-v0.10.4-x86_64-unknown-linux-gnu.tar.gz | tar xz -C /usr/local/bin; \
    elif [ "$ARCH" = "arm64" ]; then \
        curl -sL https://github.com/lotabout/skim/releases/download/v0.10.4/skim-v0.10.4-aarch64-unknown-linux-gnu.tar.gz | tar xz -C /usr/local/bin; \
    fi

# Install gh CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash hiiro
USER hiiro
WORKDIR /home/hiiro

# Set up directory structure
RUN mkdir -p ~/work ~/proj ~/bin ~/.config/hiiro/{pins,tasks,sounds,plugins}

# Configure git
RUN git config --global user.email "test@example.com" \
    && git config --global user.name "Test User" \
    && git config --global init.defaultBranch main

# Copy hiiro source first (for dependency installation)
COPY --chown=hiiro:hiiro Gemfile Gemfile.lock hiiro.gemspec /home/hiiro/work/hiiro-source/
COPY --chown=hiiro:hiiro lib/hiiro/version.rb /home/hiiro/work/hiiro-source/lib/hiiro/

# Install Ruby dependencies (cached layer)
WORKDIR /home/hiiro/work/hiiro-source
RUN bundle config set --local path vendor/bundle && bundle install

# Copy full hiiro source
COPY --chown=hiiro:hiiro . /home/hiiro/work/hiiro-source

# Create a bare repository for worktree testing
# This repo is separate from the hiiro source
RUN mkdir -p ~/work/testrepo/.bare \
    && cd ~/work/testrepo/.bare \
    && git init --bare \
    && cd ~/work/testrepo \
    && git clone .bare main \
    && cd main \
    && echo "# Test Repo" > README.md \
    && git add README.md \
    && git commit -m "Initial commit" \
    && git push origin main

# Set working directory to hiiro source
WORKDIR /home/hiiro/work/hiiro-source

# Add bin to PATH and set RUBYLIB
ENV PATH="/home/hiiro/bin:/home/hiiro/work/hiiro-source/bin:${PATH}"
ENV RUBYLIB="/home/hiiro/work/hiiro-source/lib"

# Default command
CMD ["/bin/bash"]
