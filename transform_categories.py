#!/usr/bin/env python3
"""Rebuild Noah's 2 Apple Reminders categories as Nudge lists + fix recurrence.
Operates on CURRENT cloud data (preserves any changes Noah made)."""
import json, urllib.request

SUPA = "https://epaiazxcdcseijkhrncm.supabase.co"
ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwYWlhenhjZGNzZWlqa2hybmNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMjQ0MzQsImV4cCI6MjA5MjYwMDQzNH0.h2t_kFLZ_YPvuJlzPPiyXVbOnW4Ub_52hdaYosMoOus"
UK = "2631e558-19f1-4961-9502-d701f4b15826"
H = {"apikey": ANON, "Authorization": f"Bearer {ANON}", "Content-Type": "application/json"}

MONTHLY = {"freq": "monthly", "interval": 1}
YEARLY  = {"freq": "yearly", "interval": 1}
WEEKLY  = {"freq": "weekly", "interval": 1}
def daily(n): return {"freq": "daily", "interval": n}

# title -> (listId, recurrence-or-None)
SUBS = "finance"   # the Finance list, renamed below to "Subscriptions/Money"
IMP  = "important"
MAP = {
  # --- Subscriptions/Money (all monthly) ---
  "Pay Amazon Subscribe & Save": (SUBS, MONTHLY),
  "Calculate Next Pay Amount - Use Confirm Monthly Schedule Button on KOT": (SUBS, MONTHLY),
  "Pay £1.99 for One Sec": (SUBS, MONTHLY),
  "Pay Preply Japanese Tutor Fee": (SUBS, MONTHLY),
  "Sony Bank Monthly Savings": (SUBS, MONTHLY),
  "Paidy Apple Device Payment - ¥9,916": (SUBS, MONTHLY),
  "Pay £2.99 iCloud+": (SUBS, MONTHLY),
  "Pay ¥3,500 for Claude Pro": (SUBS, MONTHLY),
  "Add £4.98 to Apple Account Balance via App Store - Keep £5.99 in Subscription Pocket on Revolut": (SUBS, MONTHLY),
  "Pay £5.99 for Netflix": (SUBS, MONTHLY),
  # --- Important ---
  "KP Body Scrub Night": (IMP, daily(3)),
  "Make Ginger Shots": (IMP, WEEKLY),
  "Go to Lebanese Restaurant with Lara & Mum - 池袋": (IMP, None),
  "Buy Pens & Refill for Father's Day": (IMP, None),
  "Submit Next Month's Work Schedule": (IMP, MONTHLY),
  "Renew Japanese Passport": (IMP, None),
  "Upload Revolut Receipt/Record - Silver Investment to Google Drive Folder": (IMP, MONTHLY),
  "BUY DAD's BDAY CARD & GIFT": (IMP, YEARLY),
  "BUY MUM's BDAY CARD & GIFT": (IMP, YEARLY),
  # "Epiduo Night" handled specially below (two of them, by date)
}
# Epiduo: 21 May = every 2 days, 29 May = daily
EPIDUO = {"2026-05-21": (IMP, daily(2)), "2026-05-29": (IMP, daily(1))}

# 1. pull current cloud data
req = urllib.request.Request(f"{SUPA}/rest/v1/nudge_data?user_key=eq.{UK}&select=data", headers=H)
rows = json.loads(urllib.request.urlopen(req).read())
if not rows:
    raise SystemExit("No cloud row found — nothing to transform.")
data = rows[0]["data"]
reminders = data["reminders"]
lists = data["lists"]

# 2. rename Finance -> Subscriptions/Money, add Important list
for l in lists:
    if l["id"] == "finance":
        l["name"] = "Subscriptions/Money"
if not any(l["id"] == "important" for l in lists):
    lists.append({"id": "important", "name": "Important", "color": "#D7263D", "builtin": False})

# 3. apply mapping
changed = {"subs": 0, "important": 0, "recur": 0}
for r in reminders:
    t = r["title"]
    target = None
    if t == "Epiduo Night" and r.get("dueDate"):
        day = r["dueDate"][:10]
        target = EPIDUO.get(day)
    elif t in MAP:
        target = MAP[t]
    if not target:
        continue
    list_id, rec = target
    r["listId"] = list_id
    if rec:
        r["recurrence"] = rec
        changed["recur"] += 1
    changed["subs" if list_id == SUBS else "important"] += 1

# 4. write back (upsert)
payload = {"user_key": UK, "data": data, "updated_at": __import__("datetime").datetime.utcnow().isoformat() + "Z"}
preq = urllib.request.Request(f"{SUPA}/rest/v1/nudge_data",
    data=json.dumps(payload).encode(),
    headers={**H, "Prefer": "resolution=merge-duplicates"}, method="POST")
code = urllib.request.urlopen(preq).getcode()

# report
counts = {}
for r in reminders:
    counts[r["listId"]] = counts.get(r["listId"], 0) + 1
print(f"HTTP {code}")
print(f"Reassigned → Subscriptions/Money: {changed['subs']}, Important: {changed['important']}")
print(f"Recurrence set on: {changed['recur']} reminders")
print("List counts now:", json.dumps(counts, ensure_ascii=False))
print("Lists:", [l["name"] for l in lists])
