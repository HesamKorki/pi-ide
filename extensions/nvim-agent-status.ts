import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

function statusDir(): string {
  return process.env.NVIM_AGENT_STATUS_DIR || join(tmpdir(), `pi-agent-status-${process.env.USER || "unknown"}`);
}

function emit(event: string, data: Record<string, unknown> = {}) {
  const agentId = process.env.NVIM_AGENT_ID;
  if (!agentId) return;

  const dir = statusDir();
  mkdirSync(dir, { recursive: true });
  appendFileSync(
    join(dir, "events.jsonl"),
    JSON.stringify({
      ts: Date.now(),
      pid: process.pid,
      agentId,
      event,
      ...data,
    }) + "\n",
    "utf8"
  );
}

function firstAssistantLine(messages: { role?: string; content?: unknown }[]): string | undefined {
  for (let i = messages.length - 1; i >= 0; i--) {
    const message = messages[i];
    if (message?.role !== "assistant") continue;
    const content = message.content;
    if (typeof content === "string") return content.split("\n").find(Boolean)?.slice(0, 200);
    if (Array.isArray(content)) {
      for (const part of content) {
        if (part && typeof part === "object" && "text" in part && typeof part.text === "string") {
          return part.text.split("\n").find(Boolean)?.slice(0, 200);
        }
      }
    }
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    emit("session_start", { cwd: ctx.cwd, sessionName: pi.getSessionName?.() });
  });

  pi.on("agent_start", async () => {
    emit("agent_start");
  });

  pi.on("agent_end", async (event) => {
    emit("agent_end", { summary: firstAssistantLine(event.messages as { role?: string; content?: unknown }[]) });
  });

  pi.on("session_shutdown", async () => {
    emit("session_shutdown");
  });
}
