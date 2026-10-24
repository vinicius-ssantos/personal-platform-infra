#!/usr/bin/env python3
"""Validate rendered Compose workspace isolation without printing credentials.

Usage: docker compose --profile gateway --profile workspace config --format json
       | python3 scripts/verify_workspace_private_topology.py
"""

import json
import sys


class TopologyError(ValueError):
    """Safe policy failure: do not print the underlying Compose environment."""


def require(condition: bool, rule: str) -> None:
    if not condition:
        raise TopologyError(rule)


def network_names(service: dict) -> set[str]:
    value = service.get("networks", {})
    if isinstance(value, dict):
        return set(value)
    if isinstance(value, list):
        return set(value)
    raise TopologyError("unsupported network declaration")


def validate(config: dict) -> None:
    services = config.get("services", {})
    networks = config.get("networks", {})
    require(isinstance(services, dict) and isinstance(networks, dict), "invalid compose layout")
    java = services.get("mcp-dev-workspace")
    require(isinstance(java, dict), "missing workspace service")
    require(networks.get("workspace-private", {}).get("internal") is True,
            "workspace network must be internal")
    require(network_names(java) == {"workspace-private"},
            "workspace must not join public/shared networks")
    require(not java.get("ports") and not java.get("network_mode"),
            "workspace must not publish a host port")
    require(java.get("read_only") is True, "workspace container root must be read-only")
    require(java.get("environment", {}).get("WORKSPACE_SERVER_PORT") in ("8770", 8770),
            "workspace listener port must be 8770")
    require("WORKSPACE_API_KEY" in java.get("environment", {}),
            "workspace requires a dedicated credential binding")

    gateways = ("central-mcp-gateway", "central-mcp-gateway-blue", "central-mcp-gateway-green")
    for name in gateways:
        service = services.get(name)
        require(isinstance(service, dict), f"missing gateway service: {name}")
        require({"default", "workspace-private"}.issubset(network_names(service)),
                f"gateway missing private/shared separation: {name}")
        require(service.get("environment", {}).get("GATEWAY_UPSTREAM_WORKSPACE_URL")
                == "http://mcp-dev-workspace:8770/mcp",
                f"gateway workspace URL must use private Docker DNS: {name}")
        for port in service.get("ports", []):
            require(port.get("host_ip") in ("127.0.0.1", "::1"),
                    f"gateway host port must be loopback-only: {name}")

    allowed = set(gateways) | {"mcp-dev-workspace"}
    for name, service in services.items():
        require(name in allowed or "workspace-private" not in network_names(service),
                f"non-gateway service on workspace network: {name}")
        for port in service.get("ports", []):
            require(str(port.get("target")) != "8770" and
                    str(port.get("published")) != "8770",
                    f"Java workspace port published: {name}")


def main() -> int:
    try:
        validate(json.load(sys.stdin))
    except (TopologyError, json.JSONDecodeError, TypeError, AttributeError) as error:
        print(f"workspace topology: FAIL ({error})", file=sys.stderr)
        return 1
    print("workspace topology: PASS (private network, no published Java port)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
