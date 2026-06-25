#!/usr/bin/env python3
"""Generate an importable Nudge "Morning Digest" Shortcut (.plist/.shortcut).

Fetches the shared Supabase nudge_data blob, filters to the user's own,
incomplete, dated reminders, and reads out an overdue count + today's list.
All logic is native Shortcuts actions (iOS has no JS action), so date math is
done by formatting dates to yyyyMMdd integers and comparing numerically.
"""
import plistlib, uuid

BASE = "https://epaiazxcdcseijkhrncm.supabase.co"
ANON = ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwY"
        "WlhenhjZGNzZWlqa2hybmNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMjQ0MzQsImV4cCI"
        "6MjA5MjYwMDQzNH0.h2t_kFLZ_YPvuJlzPPiyXVbOnW4Ub_52hdaYosMoOus")
USER_KEY = "2631e558-19f1-4961-9502-d701f4b15826"
URL = f"{BASE}/rest/v1/nudge_data?user_key=eq.{USER_KEY}&select=data"

def uid():
    return uuid.uuid4().hex.upper()

def var(name, aggr=None):
    v = {"Type": "Variable", "VariableName": name}
    if aggr:
        v["Aggrandizements"] = aggr
    return {"WFSerializationType": "WFTextTokenAttachment", "Value": v}

def text_with_var(parts):
    """parts: list of str | ('var', name). Returns interpolated-string token."""
    string = ""
    attachments = {}
    for p in parts:
        if isinstance(p, str):
            string += p
        else:
            ph = "￼"
            attachments[f"{{{len(string)}, 1}}"] = {"Type": "Variable", "VariableName": p[1]}
            string += ph
    return {"WFSerializationType": "WFTextTokenString",
            "Value": {"string": string, "attachmentsByRange": attachments}}

def action(ident, params=None):
    return {"WFWorkflowActionIdentifier": ident,
            "WFWorkflowActionParameters": params or {}}

A = []

# 1. Comment
A.append(action("is.workflow.actions.comment",
    {"WFCommentActionText": "Nudge — Morning Digest. Reads out overdue + today's reminders from the shared Supabase blob."}))

# 2. Get Contents of URL (with auth headers)
A.append(action("is.workflow.actions.downloadurl", {
    "WFURL": URL,
    "WFHTTPMethod": "GET",
    "WFHTTPHeaders": {"Value": {"WFDictionaryFieldValueItems": [
        {"WFItemType": 0,
         "WFKey": {"Value": {"string": "apikey"}, "WFSerializationType": "WFTextTokenString"},
         "WFValue": {"Value": {"string": ANON}, "WFSerializationType": "WFTextTokenString"}},
        {"WFItemType": 0,
         "WFKey": {"Value": {"string": "Authorization"}, "WFSerializationType": "WFTextTokenString"},
         "WFValue": {"Value": {"string": "Bearer " + ANON}, "WFSerializationType": "WFTextTokenString"}},
    ]}, "WFSerializationType": "WFDictionaryFieldValue"},
}))

# 3. Get Dictionary Value: [0].data.reminders  (response is an array)
A.append(action("is.workflow.actions.getvalueforkey", {
    "WFGetDictionaryValueType": "Value",
    "WFDictionaryKey": "data.reminders",
}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "AllReminders"}))

# 4. Today as yyyyMMdd number
A.append(action("is.workflow.actions.date", {}))  # Current Date
A.append(action("is.workflow.actions.format.date", {
    "WFDateFormatStyle": "Custom", "WFDateFormat": "yyyyMMdd"}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "TodayNum"}))

# init accumulators
A.append(action("is.workflow.actions.text", {"WFTextActionText": "0"}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "OverdueCount"}))
A.append(action("is.workflow.actions.text", {"WFTextActionText": ""}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "TodayLines"}))

# 5. Repeat with each reminder
grp = uid()
A.append(action("is.workflow.actions.repeat.each", {
    "WFControlFlowMode": 0, "GroupingIdentifier": grp,
    "WFInput": var("AllReminders")}))

# completed?
A.append(action("is.workflow.actions.getvalueforkey", {
    "WFGetDictionaryValueType": "Value", "WFDictionaryKey": "completed",
    "WFInput": var("Repeat Item")}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "Done"}))
# source
A.append(action("is.workflow.actions.getvalueforkey", {
    "WFGetDictionaryValueType": "Value", "WFDictionaryKey": "source",
    "WFInput": var("Repeat Item")}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "Src"}))
# dueDate
A.append(action("is.workflow.actions.getvalueforkey", {
    "WFGetDictionaryValueType": "Value", "WFDictionaryKey": "dueDate",
    "WFInput": var("Repeat Item")}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "Due"}))
# title
A.append(action("is.workflow.actions.getvalueforkey", {
    "WFGetDictionaryValueType": "Value", "WFDictionaryKey": "title",
    "WFInput": var("Repeat Item")}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "Title"}))

# IF Done is not 1 (i.e. not completed) AND Due has any value
ifgrp = uid()
A.append(action("is.workflow.actions.conditional", {
    "WFControlFlowMode": 0, "GroupingIdentifier": ifgrp,
    "WFInput": {"Type": "Variable", "Variable": var("Due")},
    "WFCondition": 100,  # has any value
}))

# inner IF: skip studytrack/finance — check Src != studytrack and != finance via numeric? simpler: just include; sources are user's own mostly
# Convert Due -> yyyyMMdd number   (Due is ISO string; coerce to Date first)
A.append(action("is.workflow.actions.detect.date", {"WFInput": var("Due")}))
A.append(action("is.workflow.actions.format.date", {
    "WFDateFormatStyle": "Custom", "WFDateFormat": "yyyyMMdd"}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "DueNum"}))
# Due time HH:mm
A.append(action("is.workflow.actions.detect.date", {"WFInput": var("Due")}))
A.append(action("is.workflow.actions.format.date", {
    "WFDateFormatStyle": "None", "WFTimeFormatStyle": "Short"}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "DueTime"}))

# IF DueNum == TodayNum  -> today line
ifgrp2 = uid()
A.append(action("is.workflow.actions.number", {"WFNumberActionNumber": var("DueNum")}))
A.append(action("is.workflow.actions.conditional", {
    "WFControlFlowMode": 0, "GroupingIdentifier": ifgrp2,
    "WFInput": {"Type": "Variable", "Variable": var("DueNum")},
    "WFCondition": 4,  # is equal to
    "WFNumberValue": var("TodayNum"),
}))
A.append(action("is.workflow.actions.gettext", {
    "WFTextActionText": text_with_var(["• ", ("var", "DueTime"), "  ", ("var", "Title"), "\n"])}))
A.append(action("is.workflow.actions.appendvariable", {"WFVariableName": "TodayLines"}))
# ELSE if DueNum < TodayNum -> overdue++
A.append(action("is.workflow.actions.conditional", {
    "WFControlFlowMode": 1, "GroupingIdentifier": ifgrp2}))
ifgrp3 = uid()
A.append(action("is.workflow.actions.number", {"WFNumberActionNumber": var("DueNum")}))
A.append(action("is.workflow.actions.conditional", {
    "WFControlFlowMode": 0, "GroupingIdentifier": ifgrp3,
    "WFInput": {"Type": "Variable", "Variable": var("DueNum")},
    "WFCondition": 2,  # is less than
    "WFNumberValue": var("TodayNum"),
}))
A.append(action("is.workflow.actions.math", {
    "WFMathOperation": "+", "WFMathOperand": 1, "WFInput": var("OverdueCount")}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "OverdueCount"}))
A.append(action("is.workflow.actions.conditional", {
    "WFControlFlowMode": 2, "GroupingIdentifier": ifgrp3}))
# end equal/less if
A.append(action("is.workflow.actions.conditional", {
    "WFControlFlowMode": 2, "GroupingIdentifier": ifgrp2}))
# end has-due if
A.append(action("is.workflow.actions.conditional", {
    "WFControlFlowMode": 2, "GroupingIdentifier": ifgrp}))
# end repeat
A.append(action("is.workflow.actions.repeat.each", {
    "WFControlFlowMode": 2, "GroupingIdentifier": grp}))

# 6. Build the digest text
A.append(action("is.workflow.actions.gettext", {
    "WFTextActionText": text_with_var([
        "Good morning! You have ", ("var", "OverdueCount"), " overdue.\n\nToday:\n",
        ("var", "TodayLines")])}))
A.append(action("is.workflow.actions.setvariable", {"WFVariableName": "Digest"}))

# 7. Speak + show
A.append(action("is.workflow.actions.speaktext", {
    "WFText": var("Digest"), "WFSpeakTextWait": True}))
A.append(action("is.workflow.actions.showresult", {
    "Text": var("Digest")}))

wf = {
    "WFWorkflowClientVersion": "2607.1",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": {
        "WFWorkflowIconStartColor": 4282601983,
        "WFWorkflowIconGlyphNumber": 61440,
    },
    "WFWorkflowImportQuestions": [],
    "WFWorkflowTypes": ["NCWidget", "WatchKit"],
    "WFWorkflowInputContentItemClasses": [
        "WFAppStoreAppContentItem", "WFArticleContentItem", "WFContactContentItem",
        "WFDateContentItem", "WFEmailAddressContentItem", "WFGenericFileContentItem",
        "WFImageContentItem", "WFiTunesProductContentItem", "WFLocationContentItem",
        "WFDCMapsLinkContentItem", "WFAVAssetContentItem", "WFPDFContentItem",
        "WFPhoneNumberContentItem", "WFRichTextContentItem", "WFSafariWebPageContentItem",
        "WFStringContentItem", "WFURLContentItem",
    ],
    "WFWorkflowActions": A,
}

with open("Nudge Morning Digest.shortcut", "wb") as f:
    plistlib.dump(wf, f)
print("wrote Nudge Morning Digest.shortcut with", len(A), "actions")
