# Release notes

Notes shown to users in the **Sparkle update dialog** and on the **GitHub Release** page.

Before cutting a release, drop a file here named after the tag — e.g. `v1.1.2.md` — with one bullet per change:

```markdown
- Fixed the menu bar bar flickering on wake
- Added a Fable usage row
```

Then run `make release VERSION=1.1.2`. The release script picks up `release-notes/v1.1.2.md` automatically, embeds it (as HTML) into `appcast.xml` for Sparkle, and uses it as the GitHub Release body.

Precedence, highest first:
1. `NOTES="..."` environment variable — `NOTES=$'- quick fix' make release VERSION=1.1.3`
2. `release-notes/v<version>.md`
3. Fallback: commit subjects since the previous tag.
