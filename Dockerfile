# syntax=docker/dockerfile:1
FROM debian:bookworm-slim

LABEL maintainer="Christophe Ivorra <ch.ivorra@free.fr>" \
      description="Chorus Engine — inference engine + document extraction skills (from GitHub, branch main)"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CHORUS_HOME=/opt/chorus \
    SANDBOXES=/sandboxes \
    PERL5LIB=/opt/chorus/lib \
    PATH=/opt/chorus/bin:$PATH \
    ANTHROPIC_API_KEY=""

# --- System packages: Perl, Python, LibreOffice headless, PDF tools, git, Node.js --
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        ca-certificates \
        curl \
        gnupg \
        perl \
        cpanminus \
        libyaml-perl \
        libtest-simple-perl \
        libtest-warn-perl \
        python3 \
        python3-pip \
        poppler-utils \
        libxml2-utils \
        libreoffice-core \
        libreoffice-calc \
        libreoffice-writer \
        fonts-dejavu \
        fonts-liberation \
        nodejs \
        npm \
    && rm -rf /var/lib/apt/lists/*

# --- Perl deps not covered by apt (pure-Perl, no compile needed) ----------
RUN cpanm --notest --no-man-pages \
        JSON \
        Digest::MD5 \
        File::Temp \
    && rm -rf /root/.cpanm

# --- Python deps: extraction skills + Anthropic API for skill generation ----
RUN pip3 install --no-cache-dir --break-system-packages \
        pdfminer.six \
        pypdf \
        pdfplumber \
        Pillow \
        python-docx \
        openpyxl \
        beautifulsoup4 \
        lxml \
        anthropic

# --- Upgrade Node.js to 22.x (required for Claude Code) ---
RUN npm install -g n && n 22

# --- Claude Code CLI (Official Anthropic, via npm) ---
RUN npm install -g @anthropic-ai/claude-code

ARG CHORUS_REF=main
RUN git clone --branch ${CHORUS_REF} --depth 1 \
        https://github.com/civorra/Chorus.git ${CHORUS_HOME}

WORKDIR ${CHORUS_HOME}

# Build & install (Chorus::*, Chorus::Frame, Chorus::Engine, Chorus::Expert…)
RUN perl Makefile.PL && make && make test

# --- Sandboxes: mounted at runtime, never baked into the image ------------
RUN mkdir -p ${SANDBOXES}
VOLUME ["${SANDBOXES}"]

WORKDIR ${SANDBOXES}

# --- Welcome message + usage instructions ---
RUN cat >> /root/.bashrc << 'BASHRC_EOF'

# Chorus Engine container
echo "🎼 Chorus Engine — Docker Container (with Claude Code CLI)"
echo "=========================================================="
echo ""
echo "Available commands:"
echo "  chorus-pdf ...        — Extract PDF documents"
echo "  chorus-word ...       — Extract Word documents"
echo "  chorus-excel ...      — Extract Excel spreadsheets"
echo "  chorus-feed ...       — Enrich sandbox KB from corpus"
echo "  chorus-check ...      — Run compliance verification"
echo "  claude                — Claude Code (official, by Anthropic)"
echo ""
echo "Quick start:"
echo "  cd /sandboxes/<your-project>"
echo "  claude                                  # Start interactive session"
echo "  claude 'ask me anything'                # Single task"
echo "  claude /init                            # Create project guidelines"
echo "  claude /help                            # Show all commands"
echo ""
echo "First use:"
echo "  Run 'claude' → authentication via browser or API key"
echo "  Supported: Claude Pro/Max/Teams/Enterprise, Console (API), Bedrock, Vertex AI"
echo ""
echo "Chorus extraction examples:"
echo "  eca chorus-pdf . corpus/001-doc.pdf --out doc"
echo "  eca chorus-feed . corpus/NNN-doc-vision.md"
echo "  eca chorus-check . projet-cross.json"
echo ""
echo "Environment variable (pass with -e flag):"
echo "  ANTHROPIC_API_KEY — Your API key (for Console/cloud accounts only)"
echo ""
echo "Current API Key: ${ANTHROPIC_API_KEY:-(not set)}"
echo ""
BASHRC_EOF

WORKDIR ${CHORUS_HOME}

ENTRYPOINT ["/bin/bash"]
# ENTRYPOINT ["/usr/local/bin/claude"]
