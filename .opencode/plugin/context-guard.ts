import { execSync } from "child_process";
import type { Plugin } from "@opencode-ai/plugin";

function getKubeContext(): string {
  try {
    return execSync("kubectl config current-context", {
      encoding: "utf-8",
      timeout: 2000,
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch {
    return "unknown";
  }
}

function classifyContext(ctx: string): "vps" | "local" | "unknown" {
  const lower = ctx.toLowerCase();
  if (lower.includes("vps") || lower.includes("k3s") || lower.includes("prod")) return "vps";
  if (lower.includes("k3d") || lower.includes("local") || lower === "default") return "local";
  return "unknown";
}

function isUnsafeOnVps(cmd: string): boolean {
  return /\b(delete\s+(deploy|sts|ds|pod|svc|ingress)|drain|delete\s+namespace|delete\s+clusterrole)\b/i.test(cmd);
}

export default (async () => {
  return {
    "tool.execute.before": (input: any, output: any) => {
      const toolName = input?.name || input?.tool;
      if (toolName !== "bash") return;

      const cmd = output?.args?.command || "";
      if (!cmd || cmd.length < 3) return;

      const ctx = getKubeContext();
      const env = classifyContext(ctx);

      const badges: string[] = [];
      const desc = output?.args?.description || "";

      if (env === "vps") badges.push("[VPS]");
      else if (env === "local") badges.push("[k3d]");

      if (isUnsafeOnVps(cmd) && env === "vps") {
        output.args.description = `!! VPS DELETE !! ${desc}`;
        return;
      }

      if (/\bsops\b/i.test(cmd)) badges.push("[sops]");
      if (/\.enc\.yaml/i.test(cmd)) badges.push("[encrypted-secret]");
      if (env !== "unknown") badges.push(`(${ctx})`);

      if (badges.length > 0) {
        output.args.description = `${badges.join(" ")} ${desc}`.trim();
      }
    },
  };
}) satisfies Plugin;
