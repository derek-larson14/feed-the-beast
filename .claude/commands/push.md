---
description: Git commit and push with auto-generated message
allowed-tools: [Bash]
---

# Git Push with Auto-generated Commit Message

!git status
!git diff --staged
!git diff

Analyze the changes above and create a concise, descriptive commit message that reflects the actual work being done. Then:

!git add -A
!git commit -m "YOUR_GENERATED_MESSAGE_HERE"
!git push

The commit message should:
- Summarize the main changes clearly
- Be under 72 characters for the first line
- Be specific about what changed
- Use appropriate tone and formatting for your project (technical vs. business language)