# Using a coding agent

You can use an AI coding agent (GitHub Copilot in VS Code/Codespaces, Claude Code, OpenAI Codex, Cursor
and others) as a lab partner. The repository ships guidance so your agent understands this
environment:

| File | Read by | Contains |
|---|---|---|
| `AGENTS.md` | Copilot, Codex, Cursor, Gemini CLI, most agents | How KID is wired, safety rules, where things live, how to validate changes |
| `CLAUDE.md` | Claude Code | Imports `AGENTS.md` |
| `.agents/skills/` | Agents that support [Agent Skills](https://agentskills.io) (also linked as `.claude/skills` and `.github/skills`) | Step-by-step procedures, loaded only when relevant |

## Skills

| Skill | Ask things like... |
|---|---|
| `kid-lab-guide` | "I'm on lab 3 step 2, why did my connection time out?" · "Give me a hint for lab 6 question 3" |
| `kid-network-policy` | "Let project beta install packages from PyPI" · "Show me what alpha's workspace tried to reach" |
| `kid-new-project` | "Create project gamma with medium workspaces and give researcher2 access" |
| `kid-kyverno-policy` | "Why was my pod rejected?" · "Write an Audit policy that requires a cost-centre label" |
| `kid-workspace-config` | "Make idle workspaces stop after 10 minutes" · "Add a large size to project beta" |
| `kid-troubleshoot` | "Argo CD says unable to resolve revision" · "My workspace won't start" |

## Tips

- **Run the agent inside the dev container** (the default in Codespaces and VS Code Dev Containers).
  That's where `kubectl`, `hubble` and friends can reach the cluster.
- The guidance tells the agent to **teach rather than just solve**: it gives hints for the "Check
  your understanding" questions unless you ask for the answer. Ask it to explain its commands.
- The agent is told **not to weaken guardrails** (network policies, Kyverno, quotas) to make
  something work, and to ask before destructive actions. If a lab *is* about breaking something,
  say so.
- Changes under `gitops/` only reach the cluster after you commit and push to your fork (then
  `tre sync`). The agent should tell you which changes are GitOps and which are direct `kubectl`.
- Treat agent output like a colleague's: read the diff before you commit it.
