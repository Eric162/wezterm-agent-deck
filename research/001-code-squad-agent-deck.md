# Agent Management Tool Research Document

> Generated: Thu Jan 08 2026
> Scope: Analysis of agent-deck and code-squad for command detection and agent completion mechanisms
> Focus: How these tools detect running commands and determine when AI agents have finished

## Executive Summary

- **Both tools use pattern-based detection** to identify AI agent states from terminal output
- **agent-deck** uses tmux sessions with activity timestamps and content hashing for state detection
- **code-squad** uses VS Code's shell integration events with output buffering and idle timeouts
- **Key challenge**: Distinguishing "agent thinking" from "agent waiting for user input"
- **Common patterns detected**: "Esc to interrupt" (working), "Esc to cancel" / Y/n prompts (waiting), ">" prompt (idle)

---

## 1. Agent-Deck Overview

| Attribute | Value |
|-----------|-------|
| Repository | [asheshgoplani/agent-deck](https://github.com/asheshgoplani/agent-deck) |
| Language | Go |
| UI Framework | Bubble Tea (TUI) |
| Terminal Management | tmux sessions |
| Platform | macOS, Linux, WSL |

### 1.1 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Agent-Deck TUI                            │
├─────────────────────────────────────────────────────────────────┤
│  Session Manager     │  Status Detector    │  MCP Pool Manager  │
│  (internal/session)  │  (internal/tmux)    │  (internal/mcppool)│
├─────────────────────────────────────────────────────────────────┤
│                          tmux API                                │
│              (sessions, panes, pipe-pane logging)                │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Status Model

Agent-deck uses a **3-state notification model**:

| Status | Color | Meaning | Detection |
|--------|-------|---------|-----------|
| **active** | Green | Agent is working | Busy indicators OR recent activity |
| **waiting** | Yellow | Needs user attention | Cooldown expired, not acknowledged |
| **idle** | Gray | User has seen it | Cooldown expired, acknowledged |

---

## 2. Code-Squad Overview

| Attribute | Value |
|-----------|-------|
| Repository | [team-attention/code-squad](https://github.com/team-attention/code-squad) |
| Language | TypeScript |
| Platform | VS Code Extension |
| Terminal Management | VS Code integrated terminal |
| Features | Diff view, inline comments, worktree isolation |

### 2.1 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    VS Code Extension                             │
├─────────────────────────────────────────────────────────────────┤
│  AIDetectionController   │  DetectThreadStatusUseCase           │
│  (command detection)     │  (output pattern matching)           │
├─────────────────────────────────────────────────────────────────┤
│  TerminalStatusDetector  │  FileWatchController                 │
│  (domain/services)       │  (file change tracking)              │
├─────────────────────────────────────────────────────────────────┤
│              VS Code Terminal Shell Integration API              │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Status Model

Code-squad uses a **4-state model**:

| Status | Color | Meaning | Detection |
|--------|-------|---------|-----------|
| **working** | Green (pulsing) | AI processing | "Esc to interrupt" visible |
| **waiting** | Yellow | User input needed | Permission dialogs, Y/n prompts |
| **idle** | Blue | Ready for input | Empty prompt visible |
| **inactive** | Gray | No AI session | No patterns matched |

---

## 3. Command Detection Mechanisms

### 3.1 Agent-Deck: Command Detection

**Location**: `internal/tmux/tmux.go` - `DetectTool()` method

**Primary Method**: Command string matching (most reliable)

```go
// From session.go - DetectTool()
if s.Command != "" {
    cmdLower := strings.ToLower(s.Command)
    if strings.Contains(cmdLower, "claude") {
        return "claude"
    } else if strings.Contains(cmdLower, "gemini") {
        return "gemini"
    } else if strings.Contains(cmdLower, "opencode") {
        return "opencode"
    } else if strings.Contains(cmdLower, "codex") {
        return "codex"
    }
}
```

**Fallback Method**: Content pattern matching using regex:

```go
var toolDetectionPatterns = map[string][]*regexp.Regexp{
    "claude": {
        regexp.MustCompile(`(?i)claude`),
        regexp.MustCompile(`(?i)anthropic`),
    },
    "gemini": {
        regexp.MustCompile(`(?i)gemini`),
        regexp.MustCompile(`(?i)google ai`),
    },
    // ...
}
```

**Caching**: Tool detection is cached for 30 seconds to avoid repeated expensive content captures.

### 3.2 Code-Squad: Command Detection

**Location**: `packages/vscode/src/adapters/inbound/controllers/AIDetectionController.ts`

**Primary Method**: VS Code shell execution events + regex matching

```typescript
// Command detection patterns
private isClaudeCommand(commandLine: string): boolean {
    return /^(npx\s+|bunx\s+|pnpx\s+)?claude(-code)?(\s|$)/.test(commandLine.trim());
}

private isCodexCommand(commandLine: string): boolean {
    return /^(npx\s+|bunx\s+|pnpx\s+)?codex(\s|$)/.test(commandLine.trim());
}

private isGeminiCommand(commandLine: string): boolean {
    const normalized = commandLine.trim().toLowerCase();
    return (
        /^(npx\s+|bunx\s+|pnpx\s+)?gemini(\s|$)/.test(normalized) ||
        /^npx\s+@google\/generative-ai-cli(\s|$)/.test(normalized) ||
        /^gcloud\s+ai\s+gemini(\s|$)/.test(normalized)
    );
}

private isOpenCodeCommand(commandLine: string): boolean {
    return /^(npx\s+|bunx\s+|pnpx\s+)?opencode(-ai)?(\s|$)/.test(commandLine.trim());
}
```

**Event Hooks**:
- `vscode.window.onDidStartTerminalShellExecution` - Triggers command detection
- `vscode.window.onDidEndTerminalShellExecution` - Triggers session cleanup
- `vscode.window.onDidCloseTerminal` - Handles terminal close

**Auto-Detection from Output** (fallback):

```typescript
// AI type detection patterns from terminal output
const AI_TYPE_PATTERNS = [
    { type: 'claude', patterns: [/Claude Code/i, /Anthropic/i, /\bclaude\b.*\bsonnet\b/i] },
    { type: 'gemini', patterns: [/Gemini CLI/i, /Tips for getting started/i] },
    { type: 'codex', patterns: [/OpenAI\s*Codex/i, />_\s*OpenAI/i] },
    { type: 'opencode', patterns: [/OpenCode/i, /opencode\.ai/i] },
];
```

---

## 4. Agent Status Detection (Running vs. Finished)

### 4.1 Agent-Deck: Status Detection

**Location**: `internal/tmux/detector.go` and `internal/tmux/tmux.go`

#### 4.1.1 Primary Detection: Activity Timestamps

Agent-deck uses tmux's `window_activity` timestamp for efficient detection:

```go
// GetStatus() in tmux.go
currentTS, err := s.GetWindowActivity()  // Fast: ~4ms

// Activity timestamp changed → check if sustained or spike
if s.stateTracker.lastActivityTimestamp != currentTS {
    // Track changes over 1 second window
    if s.stateTracker.activityChangeCount >= 2 {
        // Sustained activity (2+ changes in 1s) = agent working
        return "active", nil
    }
}
```

**Spike Filtering**: Single timestamp changes (like status bar updates) are filtered out. Only sustained activity (2+ changes within 1 second) triggers "active" status.

#### 4.1.2 Busy Indicator Detection

**Location**: `internal/tmux/tmux.go` - `hasBusyIndicator()`

```go
// Text-based busy indicators
busyIndicators := []string{
    "esc to interrupt",   // Claude Code main indicator
    "(esc to interrupt)", // In parentheses
    "· esc to interrupt", // With separator
}

// Spinner characters (cli-spinners "dots" pattern)
spinnerChars := []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

// Whimsical thinking words (Claude Code uses 90 different words)
// Example: "Flibbertigibbeting... (25s · 340 tokens)"
claudeWhimsicalWords := []string{
    "thinking", "pondering", "cogitating", "deliberating", ...
}
```

#### 4.1.3 Waiting/Prompt Detection

**Location**: `internal/tmux/detector.go` - `hasClaudePrompt()`

```go
// Permission prompts (normal mode)
permissionPrompts := []string{
    "No, and tell Claude what to do differently",  // Most reliable
    "Yes, allow once",
    "Yes, allow always",
    "❯ Yes",
    "❯ No",
    "Do you trust the files in this folder?",
    "Run this command?",
}

// Input prompt (--dangerously-skip-permissions mode)
// Claude shows just ">" when waiting for next input
cleanLastLine := StripANSI(lastLine)
if cleanLastLine == ">" || cleanLastLine == "> " {
    return true  // Waiting for input
}

// Y/n confirmation prompts
questionPrompts := []string{
    "Continue?", "Proceed?",
    "(Y/n)", "(y/N)", "[Y/n]", "[y/N]",
}
```

#### 4.1.4 State Machine Logic

```go
// Cooldown-based state transitions
const activityCooldown = 2 * time.Second

func (s *Session) GetStatus() (string, error) {
    // 1. Check busy indicator first (immediate GREEN)
    if s.hasBusyIndicator(content) {
        return "active", nil
    }
    
    // 2. Check activity timestamp for sustained activity
    if sustainedActivity {
        return "active", nil
    }
    
    // 3. Check cooldown (2 seconds since last change)
    if time.Since(s.stateTracker.lastChangeTime) < activityCooldown {
        return "active", nil
    }
    
    // 4. Cooldown expired → waiting or idle
    if s.stateTracker.acknowledged {
        return "idle", nil   // User has seen it (gray)
    }
    return "waiting", nil    // Needs attention (yellow)
}
```

### 4.2 Code-Squad: Status Detection

**Location**: `packages/core/src/domain/services/TerminalStatusDetector.ts`

#### 4.2.1 Pattern-Based Detection

```typescript
// Claude Code patterns (priority-ordered)
const CLAUDE_PATTERNS: StatusPattern[] = [
    {
        status: 'waiting',
        priority: 2,  // Highest priority
        patterns: [
            /Esc to cancel/i,               // Permission dialog
            />\s*1\.\s*Yes/i,                // Menu option
            /\(y\/n\)/i,
            /\[Y\/n\]/i,
            /Press Enter to continue/,
            /Do you want to proceed\?/i,
        ],
    },
    {
        status: 'working',
        priority: 1,
        patterns: [
            /Esc to interrupt/i,  // Key indicator of active processing
        ],
    },
    {
        status: 'idle',
        priority: 0,  // Lowest priority
        patterns: [
            /^>\s*$/m,  // Empty prompt
        ],
    },
];
```

#### 4.2.2 Idle Timeout Detection

**Location**: `packages/core/src/application/useCases/DetectThreadStatusUseCase.ts`

```typescript
// Time constants
private static IDLE_TIMEOUT_MS = 2000;  // 2 seconds of silence
private static MAX_BUFFER_SIZE = 100;   // Buffer for split patterns

private scheduleIdleTransition(terminalId: string, state: TerminalState): void {
    state.idleTimer = setTimeout(() => {
        if (state.status !== 'working') return;

        // If tool was in progress and no completion seen, assume waiting
        if (state.toolInProgress) {
            state.status = 'waiting';
            this.notifyChange(terminalId, 'waiting');
            return;
        }

        // Otherwise, agent is idle
        state.status = 'idle';
        this.notifyChange(terminalId, 'idle');
    }, DetectThreadStatusUseCase.IDLE_TIMEOUT_MS);
}
```

#### 4.2.3 Tool Execution Tracking

```typescript
// Detect tool execution patterns
const TOOL_EXECUTION_PATTERN = /⏺\s*(Write|Bash|Read|Edit|Glob|Grep|MultiEdit|TodoRead|TodoWrite|WebFetch|WebSearch)/;

processOutput(terminalId: string, aiType: AIType, output: string): void {
    // Check for tool execution
    if (TOOL_EXECUTION_PATTERN.test(cleanOutput)) {
        state.toolInProgress = true;
    }
    
    // If tool in progress but no more output → waiting for permission
}
```

#### 4.2.4 Output Buffering

```typescript
processOutput(terminalId: string, aiType: AIType, output: string): void {
    // Handle screen clear sequences
    const clearScreenRegex = /\x1b\[2J/g;
    if (lastClearIndex !== -1) {
        state.rawBuffer = '';  // Reset buffer on screen clear
    }
    
    // Check current chunk first (handles large outputs)
    const chunkStatus = this.detector.detect(effectiveAIType, cleanOutput);
    if (chunkStatus !== 'inactive') {
        // Pattern found - use immediately
        return;
    }
    
    // Buffer for patterns split across chunks
    state.rawBuffer += cleanOutput;
    if (state.rawBuffer.length > MAX_BUFFER_SIZE) {
        state.rawBuffer = state.rawBuffer.slice(-MAX_BUFFER_SIZE);
    }
}
```

---

## 5. Comparison Summary

| Feature | Agent-Deck | Code-Squad |
|---------|------------|------------|
| **Platform** | CLI (tmux) | VS Code Extension |
| **Language** | Go | TypeScript |
| **Command Detection** | Command string + content regex | Shell execution events + regex |
| **Status States** | 3 (active/waiting/idle) | 4 (working/waiting/idle/inactive) |
| **Activity Detection** | tmux `window_activity` timestamp | Output streaming with idle timeout |
| **Busy Detection** | "esc to interrupt", spinners, thinking words | "Esc to interrupt" |
| **Waiting Detection** | Permission prompts, Y/n, ">" prompt | Permission prompts, Y/n |
| **Idle Detection** | Cooldown (2s) + acknowledged flag | Idle timeout (2s) + ">" prompt |
| **Spike Filtering** | Yes (sustained activity check) | No (uses timeout instead) |
| **Buffer/History** | Full pane capture + pipe-pane | 100 char rolling buffer |
| **ANSI Stripping** | Yes | Yes |

---

## 6. Key Implementation Patterns

### 6.1 Detecting "Agent is Working"

Both tools look for **"Esc to interrupt"** as the primary indicator:

```go
// Agent-deck
busyIndicators := []string{"esc to interrupt"}
```

```typescript
// Code-squad
{ status: 'working', patterns: [/Esc to interrupt/i] }
```

### 6.2 Detecting "Agent is Waiting for Input"

Both check for permission prompts and Y/n questions:

```go
// Agent-deck
permissionPrompts := []string{
    "Yes, allow once",
    "No, and tell Claude what to do differently",
    "(Y/n)", "[Y/n]",
}
```

```typescript
// Code-squad
{ status: 'waiting', patterns: [
    /Esc to cancel/i,
    /\(y\/n\)/i,
    /Do you want to proceed\?/i,
]}
```

### 6.3 Detecting "Agent has Finished"

**Agent-deck**: Uses cooldown (2 seconds of no activity) + acknowledgment tracking

**Code-squad**: Uses idle timeout (2 seconds) + ">" prompt detection

### 6.4 Handling ANSI Escape Codes

Both tools strip ANSI codes before pattern matching:

```go
// Agent-deck - StripANSI()
func StripANSI(content string) string {
    // Remove CSI sequences: ESC [ ... letter
    // Remove OSC sequences: ESC ] ... BEL
}
```

```typescript
// Code-squad
const ANSI_REGEX = /\x1B\[[0-9;]*[a-zA-Z]/g;
function stripAnsiCodes(text: string): string {
    return text.replace(ANSI_REGEX, '');
}
```

---

## 7. Recommendations for Your Agent Management Tool

### 7.1 Command Detection

1. **Use multiple detection methods**:
   - Primary: Match command name (`claude`, `gemini`, etc.)
   - Fallback: Detect from terminal output (banner/branding text)

2. **Support package managers**: `npx`, `bunx`, `pnpx` prefixes

3. **Cache detected tool type** to avoid repeated expensive checks

### 7.2 Status Detection

1. **Primary indicator**: Look for "Esc to interrupt" = agent is working

2. **Waiting detection** (highest priority):
   - "Esc to cancel" (permission dialogs)
   - Y/n or Yes/No prompts
   - Menu selection indicators (❯)

3. **Idle detection**:
   - Empty ">" prompt
   - Idle timeout (2 seconds of no output)

4. **Use activity-based detection** if platform supports it (tmux timestamps, VS Code shell events)

### 7.3 Anti-Flicker Strategies

1. **Cooldown period**: Don't immediately switch to idle; wait 2 seconds

2. **Spike filtering**: (Agent-deck approach) Require sustained activity (2+ changes in 1 second)

3. **Buffer patterns**: Handle patterns split across output chunks

4. **Screen clear handling**: Reset buffer when terminal clears (`ESC[2J`)

### 7.4 Terminal Output Capture

| Platform | Method |
|----------|--------|
| tmux | `tmux capture-pane` or `pipe-pane` to log file |
| VS Code | `onDidWriteTerminalData` or shell integration events |
| WezTerm | Pane capture API or `wezterm cli get-text` |
| Raw PTY | Direct PTY read with pseudo-terminal |

---

## 8. File References

### Agent-Deck Key Files

| File | Purpose |
|------|---------|
| `internal/tmux/detector.go` | Prompt detection for Claude, Gemini, OpenCode, Codex |
| `internal/tmux/tmux.go` | Session management, status tracking, activity detection |
| `internal/session/claude.go` | Claude-specific session handling |
| `internal/session/gemini.go` | Gemini-specific session handling |

### Code-Squad Key Files

| File | Purpose |
|------|---------|
| `packages/core/src/domain/services/TerminalStatusDetector.ts` | Pattern definitions for all AI tools |
| `packages/core/src/application/useCases/DetectThreadStatusUseCase.ts` | State machine with timers |
| `packages/vscode/src/adapters/inbound/controllers/AIDetectionController.ts` | VS Code integration, command detection |
| `packages/core/src/application/ports/outbound/ITerminalPort.ts` | Terminal abstraction interface |

---

## 9. Claude Code Specific Patterns

Since Claude Code is the most common target, here's a comprehensive pattern list:

### 9.1 Working Indicators
- `esc to interrupt` (main indicator)
- Spinner characters: `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`
- `Thinking... (Xs · Y tokens)`
- `Connecting... (Xs · Y tokens)`
- 90 whimsical "thinking" words + tokens pattern

### 9.2 Waiting Indicators
- `No, and tell Claude what to do differently`
- `Yes, allow once` / `Yes, allow always`
- `❯ Yes` / `❯ No`
- `Do you trust the files in this folder?`
- `Run this command?` / `Execute this?`
- `Continue?` / `Proceed?`
- `(Y/n)` / `[Y/n]` / `(y/N)` / `[y/N]`
- `Approve this plan?`

### 9.3 Idle Indicators
- `>` (empty prompt at end of line)
- `> ` (prompt with space)
- Task completion messages + ">" prompt

### 9.4 Tool Execution Indicators
- `⏺ Write` / `⏺ Bash` / `⏺ Read` / `⏺ Edit`
- `⏺ Glob` / `⏺ Grep` / `⏺ MultiEdit`
- `⏺ TodoRead` / `⏺ TodoWrite`
- `⏺ WebFetch` / `⏺ WebSearch`

---

## Appendix A: Status Detection Flowchart

```
┌──────────────────────────────────────────────────────────────────┐
│                    Terminal Output Received                       │
└──────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Strip ANSI Escape Codes                       │
└──────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│              Check for "Esc to interrupt" pattern                 │
└──────────────────────────────────────────────────────────────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
         [Found]                           [Not Found]
              │                                 │
              ▼                                 ▼
      ┌───────────┐             ┌──────────────────────────────────┐
      │  WORKING  │             │  Check for waiting patterns       │
      │  (Green)  │             │  (Y/n, permission prompts, etc.)  │
      └───────────┘             └──────────────────────────────────┘
                                               │
                               ┌───────────────┴───────────────┐
                               │                               │
                          [Found]                         [Not Found]
                               │                               │
                               ▼                               ▼
                       ┌───────────┐            ┌──────────────────────────┐
                       │  WAITING  │            │  Check for idle patterns  │
                       │  (Yellow) │            │  (empty prompt, timeout)  │
                       └───────────┘            └──────────────────────────┘
                                                              │
                                              ┌───────────────┴───────────────┐
                                              │                               │
                                         [Found]                    [Timeout Expired]
                                              │                               │
                                              ▼                               ▼
                                      ┌───────────┐                   ┌───────────┐
                                      │   IDLE    │                   │   IDLE    │
                                      │  (Blue)   │                   │  (Blue)   │
                                      └───────────┘                   └───────────┘
```

---

## Appendix B: Supported AI Tools

| Tool | Command | Detection Patterns |
|------|---------|-------------------|
| Claude Code | `claude` | "Esc to interrupt", permission prompts |
| Gemini CLI | `gemini` | "esc to cancel", "gemini>" |
| OpenAI Codex | `codex` | "codex>", "Continue?" |
| OpenCode | `opencode` | Similar to Claude (same model) |
| Aider | `aider` | Shell prompt patterns |
| Cursor | `cursor` | Similar to Claude |
