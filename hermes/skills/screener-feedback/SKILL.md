---
name: screener-feedback
description: "After the user ignores (or accepts) a triage candidate in Talaria, find out why and turn it into a rule the screener will follow next scan."
version: 1.0.0
author: Narayan Sainaney
metadata:
  hermes:
    tags: [triage, screener, rules, talaria]
---

# Screener feedback

The user just made a decision on a triage candidate in Talaria and tapped "Why?". The first
message carries the item (source, sender or chat or repo, title, excerpt, the screener's why)
and the decision. The goal is a rule the screener can apply, written down where it reads it.

## Steps

1. Look first: `context_candidate {item_id}` for this item's verdict and decisions, `context_decisions`
   for the same sender, chat, repo or meeting series, and `context_rule {action: "list"}` for the
   rules already in force. Say what you found in one line ("You ignored 6 of 7 from Namecheap this
   month; the one you kept was a renewal notice").
2. Ask one question that separates the rule from the instance: is it this sender, this kind of
   mail, this person, this repo, this label, or only this one item? Offer the split you think is
   right.
3. Propose the rule as one fenced `rule` block and wait for Save:

```rule
scope: sender:billing@namecheap.com | chat:<name> | repo:<org/name> | person:<name> | meeting:<series>
rule: <one sentence the screener can apply, e.g. "skip promotions and sales; keep renewals,
       expiries and invoices and suggest a reminder a few days before the date">
```

4. On "save" (or "yes"), store it with `context_rule {action: "add", text: "<scope>: <rule>"}`, one
   sentence of at most 500 characters, and confirm in one line with the rule's number. To soften an
   existing rule use `update` with `active: false` rather than `delete`, so the history stays. Also
   record the reason on the item itself: `context_task {action: "decide", item_id, decision, note}`
   with the reason in the user's words, since the screener reads that note on later items from the
   same sender or chat. Rules apply to later screens only; if the user wants the last days looked
   at again, offer `context_scan {days, sources}`.
5. If the decision was "me" or "agent" and the user tapped Why anyway, the rule is a positive
   one ("always surface invoices from X"); handle it the same way.

Keep the whole exchange to a few lines. `context_rule list` is the source of truth the user can ask
for at any time ("what are my screener rules?"). Only if the tools are missing, append the rule as a
sentence under a scope heading to `screener-rules.md` in the Hermes home directory (create it 0640,
group `agent`); the screener reads that file too, but rules there do not show in `list`.
