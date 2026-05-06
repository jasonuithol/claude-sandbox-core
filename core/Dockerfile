FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y git curl zip python3 python3-pip python3-venv && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash -u 1000 claude
# /workspace holds bind-mount targets at runtime (project, docs, etc.) and
# also receives a CLAUDE.md symlink from entrypoint.sh. With --userns=keep-id
# the host user lands on container uid 1000, which displaces the image's
# claude user to a shifted uid (typically 999) — so a /workspace owned by
# image-uid-1000 becomes unwritable to the running user. Sticky-world-writable
# (like /tmp) sidesteps the whole mapping question.
RUN mkdir -p /workspace && chmod 1777 /workspace
USER claude
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/claude/.local/bin:$PATH"
WORKDIR /workspace
CMD ["/bin/bash"]
