# Feed the Beast

Text files and slash commands for running operations with AI.

Drop this folder on your computer. Replace the placeholder content. Run commands.

- `/daily` - What should I focus on today?
- `/weekly` - Review the week, plan what's next
- `/network` - Who in my network can help with current projects?
- `/outreach` - Draft outreach messages
- `/push` - Auto-commit and push changes

From ["Feed the Beast: AI eats software"](https://dtlarson.com/feed-the-beast).

## Setup

1. [Install Claude Code](https://claude.com/claude-code) ($20/month minimum)
2. Download this folder (green button → Download ZIP)
3. Unzip somewhere, rename to `operations` (or whatever you'd like)
4. Open terminal, navigate to folder: `cd path/to/folder`
5. Type `claude` and hit enter
6. Run `/daily` to test it works

## Replace the Example Content

The folder has placeholder files:
- `tasks.md` - Your tasks
- `roadmap.md` - Your goals and deadlines
- `CLAUDE.md` - Context about your work
- `outreach.md` - People you're reaching out to
- `network.md` - Your network (optional)

## Network Search (Optional)

Add people to `network.md`:
```markdown
## Jane Smith
VP Engineering @ TechStartup Inc
jane@techstartup.com
Notes: Building AI dev tools, looking for design talent
```

Run `/network` to find who can help with current projects.

## Optional: Better Editors

**Obsidian** - Visual markdown editor with linking
**Cursor** - AI code editor that plays nice with Claude Code

## Customizing

1. **Change questions** - Edit commands to ask what matters to you
2. **Add commands** - Create new `.md` files in `.claude/commands/`
3. **Adjust paths** - Update file references if you organize differently

## Tips

### Start Simple
- Begin with `/daily` and just tasks.md
- Add more files as you go

### Keep Files Updated
- The more context in your files, the better Claude works
- Update CLAUDE.md with specifics about your work

### Improve Commands
- After using a command, ask: "What would make this better?"
- Edit the files in `.claude/commands/` directly

## File Structure

```
feed-the-beast/
├── .claude/commands/      # Slash commands
├── tasks.md               # Your tasks
├── roadmap.md            # Goals and deadlines
├── outreach.md           # Outreach tracking
├── network.md            # Your network (optional)
├── CLAUDE.md             # Context for Claude
└── logs/                 # Review logs
```

## For Developers

- **MCP Integration**: Hook up calendar, Slack, email, Notion, etc. See [MCP docs](https://docs.claude.com/en/docs/claude-code/mcp).
- **Automate**: [Schedule commands](https://docs.anthropic.com/en/docs/claude-code/github-actions), chain workflows, pull from APIs
- **Extend**: This is just text files and prompts. Build whatever you need.

---

By Derek Larson. From ["Feed the Beast: AI eats software"](https://dtlarson.com/feed-the-beast).

MIT License.