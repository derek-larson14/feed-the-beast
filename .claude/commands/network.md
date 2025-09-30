# Network Search Command

You are searching the user's network to identify relevant connections based on what they're currently working on and need help with.

## How It Works

This command reads `network.md` which contains information about everyone in your network, then suggests who to reach out to based on your current priorities.

## Search Process

### Step 1: Understand Current Needs
Look at the user's task tracking and planning files to identify priorities:
- Read `tasks.md` - What are they working on?
- Read `roadmap.md` - What upcoming goals do they have?
- Identify potential needs: expertise, intros, feedback, resources, etc.

### Step 2: Search the Network
Read through `network.md` and look for relevant matches based on:
- **What they're working on**: Does their work overlap with the user's needs?
- **Their expertise**: Do they have skills that could help?
- **What they're looking for**: Is there a mutual opportunity?
- **Recent contact**: When was the last touchpoint?
- **Their network**: Can they make valuable introductions?

**Note**: Use LLM reasoning to identify connections - not just keyword matching. Look for indirect matches and creative connections.

## Output Format

Return results organized by relevance:

**Tier 1: Perfect Match** - Immediate outreach recommended
- **Name** and role/company
- **Why Relevant**: How they can help with current priorities
- **Context**: What they're working on / interested in
- **Contact Info**: Email, LinkedIn, etc.
- **Last Contact**: When you last connected

**Tier 2: Strong Match** - Worth exploring

**Tier 3: Potential Match** - Keep in pipeline

## Example Output

```
TIER 1: PERFECT MATCH

Jane Smith - VP Engineering at TechStartup
- Why: Building AI dev tools, exactly what you need for your infrastructure project
- Context: Strong ML ops background, mentioned looking for beta testers
- Contact: jane@techstartup.com, linkedin.com/in/janesmith
- Last spoke: 2024-12-15 (3 weeks ago - good timing for follow-up)

TIER 2: STRONG MATCH
...
```