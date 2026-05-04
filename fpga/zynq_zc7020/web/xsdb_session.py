"""
xsdb_session.py -- Persistent XSDB subprocess manager.

Keeps a single XSDB process alive across requests, eliminating the ~15s
JVM startup + JTAG connect overhead on every decode. Commands are sent
via stdin and responses collected via a marker-based protocol.

Usage:
    xsdb = PersistentXSDB(xsdb_path, helpers_tcl)
    xsdb.start()           # spawn + connect + source helpers
    result = xsdb.execute("fb_decode 15 {0 1 2 3}")
    xsdb.close()
"""

import subprocess
import threading
import queue
import time
import logging
import os

logger = logging.getLogger(__name__)


class PersistentXSDB:
    """Manages a persistent XSDB subprocess with marker-based I/O sync."""

    def __init__(self, xsdb_path, helpers_tcl=None, connect_cmd=None,
                 target_filter='*A9*#0'):
        """
        Args:
            xsdb_path: Path to xsdb.bat (or xsdb on Linux).
            helpers_tcl: Path to fb_helpers.tcl to source on startup.
            connect_cmd: Custom connect command (default: "connect").
            target_filter: XSDB target filter for ARM core.
        """
        self.xsdb_path = xsdb_path
        self.helpers_tcl = helpers_tcl
        self.connect_cmd = connect_cmd or "connect"
        self.target_filter = target_filter

        self._proc = None
        self._stdout_queue = queue.Queue()
        self._stdout_thread = None
        self._stderr_thread = None
        self._lock = threading.Lock()
        self._cmd_counter = 0
        self._started = False

    # -----------------------------------------------------------------
    # Public API
    # -----------------------------------------------------------------

    def start(self):
        """Spawn XSDB, connect to JTAG, source helpers. Blocks until ready."""
        with self._lock:
            self._spawn()
            self._init_session()
            self._started = True

    def execute(self, command, timeout=30):
        """Send a TCL command and return its stdout output.

        Thread-safe. Auto-reconnects on failure and retries once.

        Args:
            command: TCL command string (single or multi-line).
            timeout: Seconds to wait for response.

        Returns:
            String containing all stdout lines from the command.

        Raises:
            RuntimeError: If command fails after retry.
        """
        with self._lock:
            try:
                return self._execute_locked(command, timeout)
            except Exception as e:
                logger.warning("Command failed (%s), attempting reconnect...", e)
                try:
                    self._kill()
                    self._spawn()
                    self._init_session()
                    return self._execute_locked(command, timeout)
                except Exception as e2:
                    raise RuntimeError(
                        f"Command failed after reconnect: {e2}") from e2

    def close(self):
        """Shut down the XSDB process."""
        with self._lock:
            self._kill()
            self._started = False

    @property
    def alive(self):
        """Check if XSDB process is still running."""
        return self._proc is not None and self._proc.poll() is None

    # -----------------------------------------------------------------
    # Internal: process management
    # -----------------------------------------------------------------

    def _spawn(self):
        """Start a new XSDB subprocess."""
        self._kill()  # clean up any existing process

        logger.info("Spawning XSDB: %s", self.xsdb_path)
        self._proc = subprocess.Popen(
            [self.xsdb_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,  # unbuffered
        )

        # Drain any existing items in queue
        while not self._stdout_queue.empty():
            try:
                self._stdout_queue.get_nowait()
            except queue.Empty:
                break

        # Start reader threads
        self._stdout_thread = threading.Thread(
            target=self._reader_thread,
            args=(self._proc.stdout, self._stdout_queue),
            daemon=True,
        )
        self._stdout_thread.start()

        self._stderr_thread = threading.Thread(
            target=self._stderr_drain_thread,
            args=(self._proc.stderr,),
            daemon=True,
        )
        self._stderr_thread.start()

        # Wait for XSDB to be ready (consume startup banner)
        time.sleep(1.0)
        self._drain_queue()

    def _kill(self):
        """Kill the XSDB process if running."""
        if self._proc is not None:
            try:
                self._proc.stdin.close()
            except Exception:
                pass
            try:
                self._proc.kill()
                self._proc.wait(timeout=5)
            except Exception:
                pass
            self._proc = None

    def _init_session(self):
        """Connect to JTAG and source helper scripts."""
        # Connect
        self._execute_locked(self.connect_cmd, timeout=15)

        # Set target to ARM core
        self._execute_locked(
            f'targets -set -filter {{name =~ "{self.target_filter}"}}',
            timeout=10,
        )

        # Source helpers
        if self.helpers_tcl and os.path.exists(self.helpers_tcl):
            tcl_path = self.helpers_tcl.replace("\\", "/")
            self._execute_locked(f'source {{{tcl_path}}}', timeout=10)
            logger.info("Sourced helpers: %s", self.helpers_tcl)

    # -----------------------------------------------------------------
    # Internal: command execution with marker sync
    # -----------------------------------------------------------------

    def _execute_locked(self, command, timeout=30):
        """Send command and collect output until marker. Must hold _lock."""
        if self._proc is None or self._proc.poll() is not None:
            raise RuntimeError("XSDB process is not running")

        self._cmd_counter += 1
        marker = f"___XSDB_MARKER_{self._cmd_counter}___"

        # Send command + marker puts
        full_cmd = f"{command}\nputs \"{marker}\"\n"
        try:
            self._proc.stdin.write(full_cmd.encode("utf-8"))
            self._proc.stdin.flush()
        except (BrokenPipeError, OSError) as e:
            raise RuntimeError(f"Failed to write to XSDB stdin: {e}") from e

        # Collect lines until marker appears
        lines = []
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(
                    f"Timed out waiting for XSDB response "
                    f"(cmd #{self._cmd_counter}, {timeout}s)")
            try:
                line = self._stdout_queue.get(timeout=min(remaining, 1.0))
            except queue.Empty:
                # Check if process died
                if self._proc.poll() is not None:
                    raise RuntimeError(
                        f"XSDB process exited (rc={self._proc.returncode})")
                continue

            if marker in line:
                break
            lines.append(line)

        return "\n".join(lines)

    # -----------------------------------------------------------------
    # Internal: reader threads
    # -----------------------------------------------------------------

    @staticmethod
    def _reader_thread(pipe, q):
        """Read stdout line by line into a queue (runs in dedicated thread)."""
        try:
            for raw_line in iter(pipe.readline, b""):
                try:
                    line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
                    q.put(line)
                except Exception:
                    pass
        except Exception:
            pass

    @staticmethod
    def _stderr_drain_thread(pipe):
        """Drain stderr to prevent buffer deadlock, log warnings."""
        try:
            for raw_line in iter(pipe.readline, b""):
                try:
                    line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
                    if line.strip():
                        logger.debug("XSDB stderr: %s", line)
                except Exception:
                    pass
        except Exception:
            pass

    def _drain_queue(self):
        """Discard all pending items in the stdout queue."""
        while True:
            try:
                self._stdout_queue.get_nowait()
            except queue.Empty:
                break
