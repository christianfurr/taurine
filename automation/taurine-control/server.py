from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError
from mcp.types import ToolAnnotations
from typing import Any
import subprocess

import control

server = MCPServer(
    "Taurine", version="1.1.0",
    instructions="Control the Taurine menu bar app on this Mac. Disable allows sleep and may disconnect remote sessions. Never disable during setup or testing; use dry_run=true. No shutdown or reboot tools are provided.",
)


def invoke(action, **arguments) -> dict[str, Any]:
    try:
        return action(**arguments)
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        raise ToolError(str(error)) from error


@server.tool(structured_output=True, annotations=ToolAnnotations(readOnlyHint=True, destructiveHint=False, openWorldHint=False))
def taurine_status() -> dict[str, Any]:
    """Read Taurine state, system sleep prevention, lid state, and battery. Makes no changes."""
    return invoke(control.status)


@server.tool(structured_output=True, annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=True, openWorldHint=False))
def taurine_enable() -> dict[str, Any]:
    """Enable keep-awake, or do nothing if sleep is already disabled. A new session may need local macOS administrator approval. Readback distinguishes enabled from pending."""
    return invoke(control.enable)


@server.tool(structured_output=True, annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=True, idempotentHint=True, openWorldHint=False))
def taurine_disable(confirm_allow_sleep: bool, dry_run: bool = False) -> dict[str, Any]:
    """Allow sleep by quitting Taurine. May disconnect remote access and suspend Codex tasks. Requires explicit user intent and confirm_allow_sleep=true. For setup/testing use dry_run=true, which sends no quit request. A real request is delayed 3 seconds."""
    return invoke(control.disable, confirm_allow_sleep=confirm_allow_sleep, dry_run=dry_run)


if __name__ == "__main__":
    server.run(transport="stdio")
