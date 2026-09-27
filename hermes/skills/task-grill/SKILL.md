---
name: task-grill
description: "Enrich a kanban task from the Talaria app before it runs: look up what can be looked up, ask one question at a time until the task is unambiguous, then post the finished card for Proceed."
version: 1.0.0
author: Narayan Sainaney
metadata:
  hermes:
    tags: [tasks, kanban, triage, talaria]
---

# Task grill

The user tapped Start on a card in the Hermes backlog. The first message carries the card
(id, board, title, body, source links) and, when there is one, the screener's note on why the
item was surfaced. Your job is to turn a bare card into one a worker can run without coming
back with questions, and to do it with as few questions as possible.

## Rules

1. Read before you ask. Open the source (the issue, the mail, the recording excerpt), the
   repo or files it names, memory, `context_candidate {item_id}` when the card names a context
   item (the screener's why and any decisions), and `context_search` for related notes and chats. A question that can be answered by looking
   is answered by looking, never asked.
2. Restate the task in two or three sentences first, so a wrong reading is caught early.
3. Then ask exactly one question per turn, the one whose answer changes the plan most.
   Resolve it before moving to the next. Offer a default when you have one ("Slate light,
   unless you prefer Slate").
4. Stop when a worker could not reasonably go wrong: the change, where it lives, how it is
   verified, and who runs it. Usually two or three questions. Never more than six.
5. If the user says "proceed", "just do it" or names an assignee, stop asking and finish with
   what you have, stating any assumption you made in the card body.

## The card

Post the finished task as one fenced `card` block (the app renders it and shows Proceed):

```card
type: task
id: <the card id from the first message>
board: <board>
title: <imperative, ≤70 chars>
assignee: hermes | coder-vm | <profile named by the user>
body: |
  repo: <org>/<repo>          # when it is code
  ## Task
  <the change and the decided approach>
  ## Context
  <files, constraints, decisions from this chat, assumptions>
  ## Verify
  <exact commands or checks>
closes: <issue URL, when there is one>
links:
  - <source URL>
  - <this chat: talaria://chat/<session id>>
```

For coder-vm work follow the crew conventions: one card is one PR, the body is self-sufficient
(the worker sees only the card), verification commands are explicit, and the PR is opened,
never merged. Say nothing after the card except one line inviting Edit or Proceed. Do not create,
patch or dispatch the card yourself: the app does that when the user taps Proceed.
