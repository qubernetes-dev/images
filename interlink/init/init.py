#!/usr/bin/env python3
import datetime as dt
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import List, Optional, Tuple



# TODO: Currently allows one plugin per user, should multiple be allowed?
# (Multiple plugins running on same user at same time might break each other with bad configurations)


# Helper function for logging messages with timestamps
def log(message: str) -> None:
    ts = dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"{ts} {message}", flush=True)


# Helper function for getting env values safely
def getenv(name: str, default: Optional[str] = None, required: bool = False) -> str:
    value = os.environ.get(name, default)
    if required and (value is None or value == ""):
        raise RuntimeError(f"Required environment variable not set: {name}")
    return value or ""


# =============================================================================
# Configuration
# =============================================================================

SSH_KEY_SRC = Path("/keys/id_ed25519")
SSH_DIR = Path("/root/.ssh")
SSH_KEY = SSH_DIR / "id_ed25519"

SHARED_PORT_FILE = Path(getenv("SHARED_PORT_FILE", "/runtime/remote-port"))
SHARED_KNOWN_HOSTS_FILE = Path(getenv("SHARED_KNOWN_HOSTS_FILE", "/runtime/known_hosts"))

LOCAL_PORT_SCRIPT = Path("/opt/interlink/scripts/port.sh")
LOCAL_CONFIG_TEMPLATE = Path("/opt/interlink/config/SlurmConfig.template.yaml")
LOCAL_BINARY_ROOT = Path("/opt/interlink/binaries")

REMOTE_USER = getenv("REMOTE_USER", required=True)
REMOTE_HOST = getenv("REMOTE_HOST", required=True)
REMOTE_HOST_FINGERPRINT = getenv("REMOTE_HOST_FINGERPRINT", "")
JUMP_HOSTS = getenv("JUMP_HOSTS", "")
JUMP_HOST_FINGERPRINTS_RAW = getenv("JUMP_HOST_FINGERPRINTS", "[]")

TRY_INTERVAL = int(getenv("TRY_INTERVAL", "60"))
CONNECT_TIMEOUT = int(getenv("CONNECT_TIMEOUT", "10"))

PLUGIN_START_PORT = int(getenv("PLUGIN_START_PORT", "4000"))
PLUGIN_END_PORT = int(getenv("PLUGIN_END_PORT", "4100"))

REMOTE_BASE_DIR = getenv("REMOTE_BASE_DIR", "interlink-slurm")
DATA_ROOT_FOLDER = getenv("DATA_ROOT_FOLDER", ".local/interlink/jobs/")
SHARED_FS = getenv("SHARED_FS", "true")

# Unresolved placeholders that are still allowed to exist in the mounted Slurm
# template before init renders the final config.
ALLOWED_TEMPLATE_PLACEHOLDERS = {"PLUGIN_PORT"}


# =============================================================================
# Validation
# =============================================================================

# Validates that ssh key, port finding script and config template are present
# in current container
def validate_local_files() -> None:
    if not SSH_KEY_SRC.is_file():
        raise RuntimeError(f"SSH private key not found: {SSH_KEY_SRC}")
    if not LOCAL_PORT_SCRIPT.is_file():
        raise RuntimeError(f"Local port script not found: {LOCAL_PORT_SCRIPT}")
    if not LOCAL_CONFIG_TEMPLATE.is_file():
        raise RuntimeError(f"Local config template not found: {LOCAL_CONFIG_TEMPLATE}")


# Validates that a given json array (given as a raw string) is actually
# valid json. This is used to convert arrays given through env vars
# into arrays usable in the SSH host verification logic.
def validate_json_array(name: str, raw: str) -> List[str]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"{name} must be a valid JSON array: {exc}") from exc
    if not isinstance(value, list):
        raise RuntimeError(f"{name} must be a JSON array")
    for item in value:
        if not isinstance(item, str):
            raise RuntimeError(f"{name} must contain strings only")
    return value


# Validates all the different configuration values that are needed, and returns
# a list of jump host fingerprints if any were provided.
def validate_config() -> List[str]:
    validate_local_files()

    if PLUGIN_START_PORT > PLUGIN_END_PORT:
        raise RuntimeError("PLUGIN_START_PORT must be <= PLUGIN_END_PORT")

    jump_host_fingerprints = validate_json_array(
        "JUMP_HOST_FINGERPRINTS", JUMP_HOST_FINGERPRINTS_RAW
    )

    jump_hosts = [item.strip() for item in JUMP_HOSTS.split(",") if item.strip()]
    if jump_hosts and jump_host_fingerprints and len(jump_hosts) != len(jump_host_fingerprints):
        raise RuntimeError("JUMP_HOSTS and JUMP_HOST_FINGERPRINTS must have the same number of entries")

    return jump_host_fingerprints


# =============================================================================
# SSH helpers
# =============================================================================


# Does some preparatory steps for using ssh key.
# TODO: Was this step actually necessary?
def prepare_ssh_key() -> None:
    SSH_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SSH_KEY_SRC, SSH_KEY)
    os.chmod(SSH_DIR, 0o700)
    os.chmod(SSH_KEY, 0o600)
    log("SSH private key prepared.")


# Combines a username and remote host into a string that can be used
# with ssh (user@host)
def remote_target() -> str:
    return f"{REMOTE_USER}@{REMOTE_HOST}"


# Helper function that returns a list of the normal options for ssh connections.
def base_ssh_options() -> List[str]:
    opts = [
        "-i", str(SSH_KEY),
        "-o", "StrictHostKeyChecking=yes",
        "-o", f"UserKnownHostsFile={SHARED_KNOWN_HOSTS_FILE}",
        "-o", f"ConnectTimeout={CONNECT_TIMEOUT}",
    ]
    if JUMP_HOSTS:
        opts += ["-J", JUMP_HOSTS]
    return opts


# Helper function for running arbitrary commands on the local system shell.
def run_cmd(
    argv: List[str],
    *,
    capture: bool = True,
    check: bool = True,
    text: bool = True,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        argv,
        check=check,
        capture_output=capture,
        text=text,
    )


# Helper function for running a command over ssh on a remote host.
def run_ssh(command: str, *, capture: bool = True, check: bool = True) -> subprocess.CompletedProcess:
    remote_cmd = f"sh -lc {shlex.quote(command)}"
    argv = ["ssh", *base_ssh_options(), remote_target(), remote_cmd]
    return run_cmd(argv, capture=capture, check=check, text=True)


# Helper function for copying a file to remote destination
def copy_to_remote(local_src: Path, remote_dest: str) -> None:
    argv = ["scp", *base_ssh_options(), str(local_src), f"{remote_target()}:{remote_dest}"]
    run_cmd(argv, capture=True, check=True, text=True)


# =============================================================================
# Host key / known_hosts handling
# =============================================================================

def split_host_spec(spec: str) -> Tuple[str, int]:
    """
    Supports:
      host
      host:2222
      user@host
      user@host:2222
    """
    host_part = spec.split("@", 1)[-1]
    port = 22

    if host_part.startswith("[") and "]:" in host_part:
        host = host_part[1:host_part.index("]")]
        port = int(host_part.split("]:", 1)[1])
        return host, port

    if ":" in host_part and host_part.count(":") == 1:
        host, port_raw = host_part.rsplit(":", 1)
        if port_raw.isdigit():
            return host, int(port_raw)

    return host_part, port


def ssh_keyscan_lines(spec: str) -> List[str]:
    host, port = split_host_spec(spec)
    proc = run_cmd(["ssh-keyscan", "-p", str(port), host], capture=True, check=False, text=True)
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip() and not line.startswith("#")]
    return lines


def fingerprint_of_known_host_line(line: str) -> str:
    with tempfile.NamedTemporaryFile("w", delete=False) as tmp:
        tmp.write(line + "\n")
        tmp_path = tmp.name
    try:
        proc = run_cmd(["ssh-keygen", "-lf", tmp_path, "-E", "sha256"], capture=True, check=True, text=True)
        parts = proc.stdout.strip().split()
        if len(parts) < 2:
            raise RuntimeError(f"Could not parse fingerprint from ssh-keygen output: {proc.stdout}")
        return parts[1]
    finally:
        try:
            os.unlink(tmp_path)
        except FileNotFoundError:
            pass


# Helper function for checking that a host is reachable, as well as getting its fingerprint.
# Will try reaching host 10 times, then throws an error
def ensure_reachable_with_keyscan(host_specs: List[str]) -> None:

    max_attempts = 10

    for attempt in range(1, max_attempts + 1):
        all_ok = True

        for spec in host_specs:
            try:
                lines = ssh_keyscan_lines(spec)
            except Exception as exc:
                log(f"WARN: ssh-keyscan failed for '{spec}': {exc}")
                all_ok = False
                break

            if not lines:
                log(f"WARN: Host '{spec}' is not reachable yet (ssh-keyscan returned no keys).")
                all_ok = False
                break

        if all_ok:
            return

        if attempt < max_attempts:
            log(
                f"INFO: Host reachability attempt {attempt}/{max_attempts} failed. "
                f"Waiting {TRY_INTERVAL}s before retrying."
            )
            time.sleep(TRY_INTERVAL)

    raise RuntimeError(f"Hosts were not reachable after {max_attempts} attempts: {host_specs}")


# Checks first that a host is reachable, and then scans its fingerprint (using ensure_reachable_with_keyscan function)
# Then compares the remote host fingerprint to a user provided fingerprint (if user provided it).
# If it was not provided, create a known hosts file and trust the host anyways.
# If user provided fingerprint doesnt match, raise a runtime error.
# Does the same check both for every jump host provided, as well as the actual target remote host.
def build_known_hosts_content(jump_host_fingerprints: List[str]) -> str:
    host_specs: List[Tuple[str, Optional[str]]] = []

    jump_hosts = [item.strip() for item in JUMP_HOSTS.split(",") if item.strip()]
    for idx, jump_host in enumerate(jump_hosts):
        fp = jump_host_fingerprints[idx] if idx < len(jump_host_fingerprints) else ""
        host_specs.append((jump_host, fp or None))

    host_specs.append((REMOTE_HOST, REMOTE_HOST_FINGERPRINT or None))

    ensure_reachable_with_keyscan([spec for spec, _ in host_specs])

    lines_out: List[str] = []
    for spec, expected_fp in host_specs:
        scanned = ssh_keyscan_lines(spec)
        if not scanned:
            raise RuntimeError(f"ssh-keyscan returned no keys for host '{spec}'")

        if expected_fp:
            matched_line = None
            for line in scanned:
                fp = fingerprint_of_known_host_line(line)
                if fp == expected_fp:
                    matched_line = line
                    break
            if matched_line is None:
                raise RuntimeError(f"Fingerprint mismatch for host '{spec}'. Expected '{expected_fp}'.")
            lines_out.append(matched_line)
            log(f"Verified fingerprint for host '{spec}'.")
        else:
            lines_out.append(scanned[0])
            log(f"No fingerprint provided for host '{spec}', using scanned host key.")

    return "\n".join(lines_out) + "\n"


# Helper function for creating and writing a known hosts file.
def write_shared_known_hosts(content: str) -> None:
    SHARED_KNOWN_HOSTS_FILE.parent.mkdir(parents=True, exist_ok=True)
    SHARED_KNOWN_HOSTS_FILE.write_text(content, encoding="utf-8")
    os.chmod(SHARED_KNOWN_HOSTS_FILE, 0o600)
    log(f"Wrote known_hosts to shared path: {SHARED_KNOWN_HOSTS_FILE}")


# =============================================================================
# Remote helpers
# =============================================================================


# Escapes single quotes
def single_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


# Gets remote system architecture
def get_remote_arch() -> str:
    proc = run_ssh("uname -m", capture=True, check=True)
    return proc.stdout.strip().replace("\r", "")


# Normalizes the remote architecture to some predetermined string, that matches
# a folder name under /opt/interlink/binaries
def normalize_arch(arch: str) -> str:
    if arch in {"x86_64", "amd64"}:
        return "x86_64"
    return ""


# Matches an architecture to slurm-sd binary location. Currently only one architecture
# is supported.
def resolve_local_binary_for_arch(arch: str) -> Path:
    if arch == "x86_64":
        return LOCAL_BINARY_ROOT / "x86_64" / "slurm-sd"
    raise RuntimeError(f"No local binary mapping for architecture: {arch}")


# Runs a shell script for killing any running instance of slurm-sd, that are running under
# current users name in the remote host
def kill_remote_plugin_if_running() -> None:
    log("Checking for existing remote slurm-sd processes to kill...")
    command = r"""
set -e
PIDS="$(ps -u "$(id -un)" -o pid= -o comm= | awk '$2=="slurm-sd"{print $1}')"
if [ -n "$PIDS" ]; then
  echo "Found existing slurm-sd process(es): $PIDS"
  echo "$PIDS" | xargs kill || true
  sleep 2
  STILL="$(ps -u "$(id -un)" -o pid= -o comm= | awk '$2=="slurm-sd"{print $1}')"
  if [ -n "$STILL" ]; then
    echo "Force killing remaining slurm-sd process(es): $STILL"
    echo "$STILL" | xargs kill -9 || true
  fi
fi
"""
    run_ssh(command, capture=True, check=True)
    log("Remote slurm-sd cleanup complete.")


# Runs a shell script for ensuring that folder structures required for slurm-sd exist
# in remote host.
def ensure_remote_dirs() -> None:
    log("Ensuring remote directory structure exists...")
    command = f"""
set -e
BASE_DIR="$HOME/{REMOTE_BASE_DIR}"
DATA_ROOT_RAW={single_quote(DATA_ROOT_FOLDER)}
eval "DATA_ROOT_EXPANDED=\\"$DATA_ROOT_RAW\\""
case "$DATA_ROOT_EXPANDED" in
  /*) DATA_ROOT="$DATA_ROOT_EXPANDED" ;;
  *)  DATA_ROOT="$HOME/$DATA_ROOT_EXPANDED" ;;
esac

mkdir -p "$BASE_DIR/bin" "$BASE_DIR/config" "$BASE_DIR/scripts" "$BASE_DIR/run" "$DATA_ROOT"
"""
    run_ssh(command, capture=True, check=True)
    log("Remote directory structure ensured.")


# Writes the discovered available port into a file that is
# shared between the current init container, and the later ssh-tunnel
# container.
def write_shared_port_file(port: str) -> None:
    SHARED_PORT_FILE.parent.mkdir(parents=True, exist_ok=True)
    SHARED_PORT_FILE.write_text(port + "\n", encoding="utf-8")
    log(f"Wrote selected remote port to shared path: {SHARED_PORT_FILE}")


# Reads the shared port file (that is shared between init and ssh-tunnel containers)
def read_shared_port_file() -> str:
    if SHARED_PORT_FILE.is_file():
        return SHARED_PORT_FILE.read_text(encoding="utf-8").strip()
    return ""


# Copies all the necessary files/artifacts to remote hosts, overwriting existing
# ones if any. These include the slurm-sd binary, and port finding script. The slurm
# config file is sent only after an available port is discovered with the port.sh
# script.
def copy_remote_artifacts(binary_path: Path) -> None:
    log("Copying artifacts to remote host...")
    copy_to_remote(binary_path, f"{REMOTE_BASE_DIR}/bin/slurm-sd")
    copy_to_remote(LOCAL_PORT_SCRIPT, f"{REMOTE_BASE_DIR}/scripts/port.sh")
    run_ssh(
        f"""
set -e
chmod 755 "$HOME/{REMOTE_BASE_DIR}/bin/slurm-sd"
chmod 755 "$HOME/{REMOTE_BASE_DIR}/scripts/port.sh"
""",
        capture=True,
        check=True,
    )
    log("Remote artifacts copied.")


# Runs the port.sh script on remote host, and gets the selected port. Raises a runtime
# error upon failure.
def select_remote_port() -> str:
    preferred = read_shared_port_file()
    if preferred:
        log(f"Selecting remote port with preferred port {preferred}")
        command = (
            f"START_PORT={PLUGIN_START_PORT} END_PORT={PLUGIN_END_PORT} "
            f"PREFERRED_PORT={single_quote(preferred)} "
            f"\"$HOME/{REMOTE_BASE_DIR}/scripts/port.sh\""
        )
    else:
        log("Selecting remote port without preferred port")
        command = (
            f"START_PORT={PLUGIN_START_PORT} END_PORT={PLUGIN_END_PORT} "
            f"\"$HOME/{REMOTE_BASE_DIR}/scripts/port.sh\""
        )

    proc = run_ssh(command, capture=True, check=True)
    port = proc.stdout.strip().replace("\r", "")
    if not port:
        raise RuntimeError("Port selection returned an empty result")
    return port


# =============================================================================
# Config rendering
# =============================================================================

# Helper function that validates the mounted Slurm config template.
# At this stage only <PLUGIN_PORT> is allowed to remain unresolved.
def validate_mounted_template() -> None:
    template = LOCAL_CONFIG_TEMPLATE.read_text(encoding="utf-8")
    placeholders = set(re.findall(r"<([A-Z0-9_]+)>", template))
    disallowed = placeholders - ALLOWED_TEMPLATE_PLACEHOLDERS
    if disallowed:
        raise RuntimeError(
            f"Mounted Slurm config template contains unexpected unresolved placeholders: {sorted(disallowed)}"
        )


# Helper function that renders the final slurm config file based on discovered port.
# All other values are expected to have already been rendered into the mounted template
# by the overlay generator.
def render_template(port: str) -> str:
    template = LOCAL_CONFIG_TEMPLATE.read_text(encoding="utf-8")
    rendered = template.replace("<PLUGIN_PORT>", port)

    leftovers = set(re.findall(r"<([A-Z0-9_]+)>", rendered))
    if leftovers:
        raise RuntimeError(
            f"Final rendered Slurm config still contains unresolved placeholders: {sorted(leftovers)}"
        )

    return rendered


# Copies the final slurm config into remote host.
def copy_remote_config(rendered_config: str) -> None:
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8") as tmp:
        tmp.write(rendered_config)
        tmp_path = Path(tmp.name)

    try:
        copy_to_remote(tmp_path, f"{REMOTE_BASE_DIR}/config/SlurmConfig.yaml")
    finally:
        try:
            tmp_path.unlink()
        except FileNotFoundError:
            pass


# =============================================================================
# Remote plugin lifecycle
# =============================================================================

# Starts the plugin on the remote host, with logging into a file enabled.
def start_plugin() -> None:
    log("Starting remote slurm-sd...")
    command = f"""
set -e
BIN_PATH="$HOME/{REMOTE_BASE_DIR}/bin/slurm-sd"
CONFIG_PATH="$HOME/{REMOTE_BASE_DIR}/config/SlurmConfig.yaml"
LOG_PATH="$HOME/{REMOTE_BASE_DIR}/run/slurm.log"
SHARED_FS_VALUE={single_quote(SHARED_FS)}

if [ ! -x "$BIN_PATH" ]; then
  echo "missing binary" >&2
  exit 1
fi

if [ ! -f "$CONFIG_PATH" ]; then
  echo "missing config" >&2
  exit 1
fi

nohup env SHARED_FS="$SHARED_FS_VALUE" SLURMCONFIGPATH="$CONFIG_PATH" "$BIN_PATH" > "$LOG_PATH" 2>&1 &
"""
    run_ssh(command, capture=True, check=True)
    log("Remote slurm-sd start command issued.")


# Checks that the plugin is healthy
def check_plugin_health(port: str) -> bool:
    if not port:
        return False

    command = (
        f"curl -sf -X GET http://127.0.0.1:{port}/status "
        f"-H 'Content-Type: application/json' "
        f"-d '[]' > /dev/null"
    )
    try:
        run_ssh(command, capture=True, check=True)
        return True
    except subprocess.CalledProcessError:
        return False


# =============================================================================
# Main workflow
# =============================================================================

# The main function of the init container.
# Will crashloop the pod on any failure, after a small waiting period defined by TRY_INTERVAL
# Works roughly in following steps:
# 1. Preparatory steps (checks ssh keys, fingerprints hosts if available, checks target architecture)
# 2. Prepare remote (kill plugin if its running for some reason, copy files and overwrite existing)
# 3. Find an available port, and save it
# 4. Render the final slurm config file and send it to remote host
# 5. Start the plugin on remote host, and check after a few seconds that its actually working.
def main() -> int:
    jump_host_fingerprints = validate_config()
    
    try:
        log("Init container repair/setup cycle starting.")
        prepare_ssh_key()
        validate_mounted_template()

        known_hosts_content = build_known_hosts_content(jump_host_fingerprints)
        write_shared_known_hosts(known_hosts_content)

        raw_arch = get_remote_arch()
        normalized_arch = normalize_arch(raw_arch)
        if not normalized_arch:
            raise RuntimeError(f"Unsupported remote architecture: {raw_arch}")

        binary_path = resolve_local_binary_for_arch(normalized_arch)
        if not binary_path.is_file():
            raise RuntimeError(f"Expected local binary not found: {binary_path}")

        log(f"Remote architecture supported: raw={raw_arch} normalized={normalized_arch}")

        kill_remote_plugin_if_running()
        ensure_remote_dirs()
        copy_remote_artifacts(binary_path)

        selected_port = select_remote_port()
        log(f"Selected remote port {selected_port}")
        write_shared_port_file(selected_port)

        rendered_config = render_template(selected_port)
        copy_remote_config(rendered_config)

        start_plugin()
        time.sleep(3)

        if not check_plugin_health(selected_port):
            raise RuntimeError(f"Remote plugin did not become healthy on port {selected_port}")

        log("Init container setup completed successfully.")
        return 0

    except Exception as exc:
        log(f"ERROR: {exc}")
        log(f"INFO: Waiting {TRY_INTERVAL}s before exiting init workflow.")
        time.sleep(TRY_INTERVAL)
        sys.exit(1)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        log("Interrupted.")
        sys.exit(130)