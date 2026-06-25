#!/usr/bin/env python3
"""Fix reminders with strange early-AM Japan times (UK-trip timezone artifacts).
Re-stamps each strange reminder's original UK date+time as Japan time, so it
reads sensibly at home. Operates on current cloud data (preserves other edits)."""
import json, urllib.request
from datetime import datetime
from zoneinfo import ZoneInfo

SUPA="https://epaiazxcdcseijkhrncm.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwYWlhenhjZGNzZWlqa2hybmNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMjQ0MzQsImV4cCI6MjA5MjYwMDQzNH0.h2t_kFLZ_YPvuJlzPPiyXVbOnW4Ub_52hdaYosMoOus"
UK="2631e558-19f1-4961-9502-d701f4b15826"
H={"apikey":ANON,"Authorization":f"Bearer {ANON}","Content-Type":"application/json"}
LDN=ZoneInfo("Europe/London"); TYO=ZoneInfo("Asia/Tokyo"); UTC=ZoneInfo("UTC")

req=urllib.request.Request(f"{SUPA}/rest/v1/nudge_data?user_key=eq.{UK}&select=data",headers=H)
data=json.loads(urllib.request.urlopen(req).read())[0]["data"]

fixed=[]
for r in data["reminders"]:
    if not r.get("dueDate") or not r.get("hasTime"): continue
    inst=datetime.fromisoformat(r["dueDate"].replace("Z","+00:00"))
    jst=inst.astimezone(TYO)
    if jst.hour < 7:  # strange: middle of the night in Japan
        ldn=inst.astimezone(LDN)  # original UK date+time (the sensible numbers)
        new_inst=datetime(ldn.year,ldn.month,ldn.day,ldn.hour,ldn.minute,tzinfo=TYO).astimezone(UTC)
        old_jst=f"{jst.hour:02d}:{jst.minute:02d}"
        new_jst=f"{ldn.hour:02d}:{ldn.minute:02d}"
        r["dueDate"]=new_inst.strftime("%Y-%m-%dT%H:%M:%S.000Z")
        fixed.append((old_jst,new_jst,r["title"][:42]))

payload={"user_key":UK,"data":data,"updated_at":datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.000Z")}
preq=urllib.request.Request(f"{SUPA}/rest/v1/nudge_data",data=json.dumps(payload).encode(),
    headers={**H,"Prefer":"resolution=merge-duplicates"},method="POST")
code=urllib.request.urlopen(preq).getcode()
print(f"HTTP {code}  ·  fixed {len(fixed)} strange times (now shown in Japan time):")
for old,new,title in sorted(fixed,key=lambda x:x[1]):
    print(f"  {old} JST  →  {new} JST   {title}")
