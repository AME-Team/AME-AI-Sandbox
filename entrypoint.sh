#!/usr/bin/env bash
set -e

# --- SSH setup -------------------------------------------------------------
# Keys are only ever passed in at runtime via a read-only bind mount
# (docker run -v ~/.ssh:/etc/ssh-host:ro) — they are never baked into the
# image. Copy them into a writable, correctly-permissioned location.
SSH_DIR="${HOME}/.ssh"
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"

if [ -d /etc/ssh-host ]; then
    find /etc/ssh-host -maxdepth 1 -type f -exec cp {} "${SSH_DIR}/" \;
    chmod 600 "${SSH_DIR}"/id_* 2>/dev/null || true
    chmod 644 "${SSH_DIR}"/*.pub 2>/dev/null || true
fi

# Trust GitHub's host keys without disabling host-key checking
if ! grep -qs '^github\.com ' "${SSH_DIR}/known_hosts" 2>/dev/null; then
    ssh-keyscan -t ed25519,rsa github.com >> "${SSH_DIR}/known_hosts" 2>/dev/null || true
    chmod 644 "${SSH_DIR}/known_hosts"
fi

# --- git global identity ---------------------------------------------------
git config --global user.name  "${GIT_AUTHOR_NAME:-your-name}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-you@example.com}"

# --- git safe.directory (workspace is bind-mounted, may be owned by host root) ---
git config --global --add safe.directory '*'

# --- GitHub CLI / git HTTPS auth --------------------------------------------
# GH_TOKEN is only ever kept in the environment: gh's credential helper
# resolves it dynamically, so it is never written to disk in plaintext.
if [ -n "${GH_TOKEN}" ] && command -v gh >/dev/null 2>&1; then
    # GH_TOKEN が設定されていると gh は env のトークンを動的解決するため、auth login での
    # 保存は不要（このケースでは gh は rc=1 を返し、set -e だとコンテナが落ちる）。
    # setup-git は credential helper を設定し、トークンを env から動的解決する。
    # 失敗は握りつぶさず stderr に記録する（診断性の維持）。
    gh auth setup-git || echo "[entrypoint] warning: gh auth setup-git failed" >&2
fi

exec "$@"
