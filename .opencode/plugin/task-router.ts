import { readFileSync, existsSync } from "fs";
import { join } from "path";
import type { Plugin } from "@opencode-ai/plugin";

const AGENT_DIR = ".opencode/agent";
const FREE_TYPES = ["explore", "explorer"];
const AGENT_MAP: Record<string, string> = {
  "infra-engineer": "infra-engineer.md",
  reviewer: "reviewer.md",
  scripter: "scripter.md",
  operations: "operations.md",
  explorer: "explorer.md",
  orquestrador: "orquestrador.md",
};

function detectAgent(text: string): string | null {
  const lower = text.toLowerCase();
  for (const [key, file] of Object.entries(AGENT_MAP)) {
    if (lower.includes(key) || lower.includes(file.replace(".md", "").replace("-", " "))) {
      return file;
    }
  }
  return null;
}

function readAgentFile(baseDir: string, file: string): string | null {
  const path = join(baseDir, AGENT_DIR, file);
  if (!existsSync(path)) return null;
  return readFileSync(path, "utf-8");
}

function extractPrompt(markdown: string): string {
  const parts = markdown.split("---");
  if (parts.length >= 3) return parts.slice(2).join("---").trim();
  return markdown;
}

export default (async ({ directory }) => {
  return {
    "tool.execute.before": (input: any, output: any) => {
      const toolName = input?.name || input?.tool;
      if (toolName !== "task") return;

      const subagentType = output.args.subagent_type || "general";
      const isPaid = !FREE_TYPES.includes(subagentType);

      const prompt = output.args.prompt || "";
      const description = output.args.description || "";
      const combinedText = `${prompt} ${description}`;

      const agentFile = detectAgent(combinedText);
      if (!agentFile) return;

      const content = readAgentFile(directory, agentFile);
      if (!content) return;

      const agentPrompt = extractPrompt(content);
      const costLabel = isPaid ? "⚠️ PAID" : "✅ FREE";
      output.args.prompt = `[Contexto especializado do agent ${agentFile.replace(".md", "")}:]\n${agentPrompt}\n\n[Task:]\n${prompt}`;
      output.args.description = `[${costLabel}] task routed via ${agentFile.replace(".md", "")} agent context`;
    },
  };
}) satisfies Plugin;