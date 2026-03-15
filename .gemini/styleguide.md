# CrunchTools Claude Skill Code Review Standards

## Structure
- Skills use numbered Phases with numbered Steps
- Each phase MUST have a clear completion gate before the next phase
- Never auto-publish external artifacts — always require user approval

## Frontmatter
- YAML frontmatter is required: name, description, argument-hint, allowed-tools
- `name` field MUST match the directory name exactly
- `allowed-tools` follows least-privilege — only list tools actually used

## Memory Integration
- Content-generating skills MUST search memory for brand identity before generating
- Decision-making skills MUST store outcomes in memory
- Never apply generic AI writing patterns — match the human's established voice

## Security
- No hardcoded credentials or API keys
- All sensitive operations go through MCP tools
- Never write credentials to files or pass via command-line arguments
