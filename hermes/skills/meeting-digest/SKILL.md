---
name: meeting-digest
description: "Digest a meeting transcript attached from the Talaria app: summary, decisions, action items, memory updates and proposed reminders."
version: 1.0.0
author: Narayan Sainaney
metadata:
  hermes:
    tags: [meetings, notes, memory, reminders, talaria]
---

# Meeting digest

The user recorded a meeting on their phone. The attached text file is a transcript made on the
phone: timestamped in `[HH:MM:SS]` segments, English, punctuation added automatically, and with
no speaker labels. Names and jargon may be misheard, so prefer wording that survives a wrong word.

## Steps

1. Read the attached transcript file in full before writing anything.
2. Write the digest, in this order and kept short:
   - A one-line title with the date.
   - A summary of three to five sentences.
   - Decisions made, one line each.
   - Action items: owner, what, due date if one was said, and the `[HH:MM:SS]` where it came up.
   - Open questions.
3. Pick out durable facts worth keeping beyond this week: people and their roles, projects,
   preferences, commitments, dates. Save each with the `memory` tool. Skip anything that is only
   true for this meeting.
4. For every action item or follow-up with a date or time, propose a reminder. List the proposals
   and ask before creating any of them. Once the user confirms, create them with `cronjob_manage`.
5. Reply with the digest first, then the memory entries you saved, then the reminder proposals.

Do not send anything outside this session and do not create calendar events, emails or messages
unless the user asks. The transcript stays attached to this session for follow-up questions.
