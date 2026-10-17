"""Live verification deliberately limited to status, already-on enable, and preview."""
import asyncio
import json
from pathlib import Path
import sys
import argparse

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--server-root", type=Path, default=Path.home() / ".local/share/taurine/taurine-control")
    root = parser.parse_args().server_root.resolve()
    server = StdioServerParameters(command=sys.executable, args=[str(root / "server.py")])
    async with stdio_client(server) as streams:
        async with ClientSession(*streams) as session:
            await session.initialize()
            tools = await session.list_tools()
            assert {tool.name for tool in tools.tools} == {"taurine_status", "taurine_enable", "taurine_disable"}
            print("PASS MCP startup and discovery: three tools")
            before_result = await session.call_tool("taurine_status", {})
            before = before_result.structured_content
            assert not before_result.is_error and before["taurine_enabled"], before
            enabled = await session.call_tool("taurine_enable", {})
            assert not enabled.is_error and enabled.structured_content["changed"] is False
            print("PASS already-enabled enable is a no-op")
            preview = await session.call_tool("taurine_disable", {"confirm_allow_sleep": True, "dry_run": True})
            assert not preview.is_error
            assert preview.structured_content["dry_run"] is True
            assert preview.structured_content["changed"] is False
            rejected = await session.call_tool("taurine_disable", {"confirm_allow_sleep": False})
            assert rejected.is_error
            assert any("confirm_allow_sleep=true" in getattr(item, "text", "") for item in rejected.content)
            print("PASS disable preview and unconfirmed-disable rejection")
            after_result = await session.call_tool("taurine_status", {})
            after = after_result.structured_content
            assert after["taurine_enabled"]
            assert before["app_pids"] == after["app_pids"]
            assert before["watchdog_pids"] == after["watchdog_pids"]
            print("PASS active app and watchdog PIDs unchanged; keep-awake still enabled")
            print(json.dumps(after, indent=2))


asyncio.run(main())
