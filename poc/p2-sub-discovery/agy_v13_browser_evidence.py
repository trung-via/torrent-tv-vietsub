"""Owner-only V13.1 browser acquisition evidence boundary (source candidate).

The native producer is a trusted Owner callback, not an AGY final JSON report.
It must collect actual MCP outcomes and independent fresh-download provenance,
bind the observed file to the requested verified media, and measure runtime/FPS
on that file. No browser launch, provider I/O, polling, retry or cache write here.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import io
import json
import math
from pathlib import Path
import re
from typing import Callable
import urllib.parse
import zipfile

from agy_opensubtitles_acquisition import AgyEnglishUnavailable
from matcher import Media, preferred_media_release, parse_release
from opensubtitles import Asset, MAX_SUBTITLE_BYTES, SubtitleApiError, validate_timed_text

RECIPE_VERSION = "V13.5"
# Bump whenever local acquisition acceptance semantics change.
VERIFICATION_REVISION = "V13.4-BR07-1"
MODEL = "gemini-4-hydrogen-low"
THINKING_LEVEL = "low"
MAX_DOWNLOAD_BYTES = 6 * 1024 * 1024
os_hosts = {"www.opensubtitles.org", "opensubtitles.org"}

# Prompt retained from native BT26, with no fixture IDs, answers or paths.
RECIPE_V13_1 = "You are Hydrogen Low, Student Recipe V13.1, independently finding the English subtitle for the exact TorrServer release given below on OpenSubtitles.org via authorized ttv-browser MCP Chrome CDP 9555. No Teacher candidate IDs, answers or download links are provided. Use only list_pages, select_page, navigate_page, take_snapshot, click, fill, press_key, wait_for, evaluate_script; page-scoped calls must pass numeric pageId. Reuse only the authorized task tab. Start a fresh search from the ordinary https://www.opensubtitles.org/ search page, navigating there first if on a prior candidate detail or search result. Do not use the previous task's candidate as an answer. Use bounded visible DOM queries from the start; never dump whole DOM or subtitle text. Confirm current visible controls; observed selector hints only: #search_text, #search_submit, #bt-dwl-bt. Use visible search form title+year, select English if available; do not use arbitrary guessed search URLs. One compact read should identify search controls and current filters. Prefer compact evaluate_script reads and scoped ordinary DOM interaction with visible form controls; do not mix snapshot UIDs and CSS selectors. No read_file calls for snapshots; return small visible data directly. Avoid repeated reads. Use numeric pageId. HARD GATE: After search, verify the actual result page URL and visible heading show English-only results; selecting a language before submit does not prove it was applied. If results are mixed, follow the actual visible English filter link. Before ranking, read all relevant English candidate rows across pagination, return compact JSON {url,heading,page_title,total_english,count_scope,count_label,has_next,next_href,rows:[{href,lang,title,release,fps,badges,release_group,hi}]} on each filtered page. Read actual document.title verbatim as page_title. On this site filtered movie titles can end with English | N subtitles; use N only if that is actually present. If so set count_scope=filtered_results, count_label=the exact page_title, total_english=N. Otherwise report total_english=null, count_scope=unknown; never parse a site-wide counter. For each row read full release from visible release text or its actual title attribute, the FPS from its own date/FPS cell, badges from actual title/alt text, HI from actual hearing-impaired evidence, and release_group from the named release group (unknown if not explicit). Do not confuse a membership badge with a trusted-source badge or guess missing values, has_next means an actual enabled, visible forward page link for the SAME movie and English filter; exclude disabled buttons, unrelated navigation and page-wide Next labels. Return next_href as the actual resolved href if found, otherwise null. If the scoped result count matches the unique rows collected, do not follow unrelated pagination; if a genuine same-result next link contradicts the count, record the conflict rather than claim exhaustive coverage; lang is the actual row language or confirmed English-only list context. Do not truncate or guess counts. Only eligible English title/year rows may enter ranking. Treat row language flags flag en / en / eng / English as English only when consistent with the English-only filtered page. Prioritize correct movie/cut, measured runtime and FPS compatibility and actual trusted-source evidence over encoding resemblance, membership, download counts or uploader popularity. A trusted-source badge is supporting evidence, not proof of completeness. Choose the best evidenced compatible release. Compare other release families when useful; the number of inspected alternatives is not an acceptance condition. For each inspected detail return the actual runtime/FPS/notes and distinguish explicit evidence from unknown. If one has matching runtime, compatible cut/timing and reliable provenance while another has unknown runtime and merely closer encoding, prefer the former absent contradictory cut evidence. A RIFE interpolated ~30 FPS video may preserve original 23.976/24 FPS presentation timestamps; a nominal frame-rate difference is not itself proof of drift. Do not reject a candidate solely for nominal FPS or rescale timecodes without evidence. Never downgrade the stronger timeline/completeness evidence to meet latency targets. Do not select by a remembered candidate ID. If coverage cannot be established, report uncertainty rather than claim complete scan. For each inspected representative detail return compact JSON with url, candidate_id, title, btnVisible, fieldsetText, downloadHref (the actual href of visible ordinary #bt-dwl-bt), and downloaderChecked (boolean if the visible optional downloader checkbox exists, null if absent); read candidate-specific detail box (hint: visible download button's closest fieldset) for title/year/language, release notes including alternative supported releases, FPS, runtime, file type, visible download button and material comments in one query if practical. Check FPS/runtime against measured target metadata; unknown remains unknown. A WEB-DL and WEBRip may share a cut but the label alone proves nothing. Distinguish actual playback speed changes from frame interpolation or cadence changes. Consider progressive drift only when runtime, speed or measured timing supports it. Compare materially different runtimes and cut notes. Avoid repeatedly re-reading already confirmed pages; inspect additional candidates only when new evidence could change the choice. Distinguish exact filename/release from explicit compatible release note. Prefer completeness and timeline evidence over download count, file size or cue count alone; non-HI is a tiebreaker. Inspect next candidate only for material ambiguity or quality issue. Bind selected detail ID to the visible ordinary Download control #bt-dwl-bt, not Download (beta), preview, or downloader. If the optional installer/downloader checkbox is checked, use ordinary UI to uncheck it; do not modify site handlers or bypass restrictions. Recheck the selected ID, visible control, href and unchecked/absent downloader in the same final scoped evaluate_script action; if they match, activate that ordinary control once and return JSON {clicked:true,pageUrl,href,id,downloaderChecked}. If mismatched, do not click and report the reason. Stop browser actions after the click. A click does not establish a downloaded file. Do not guess URLs or endpoints, bypass restrictions, login, pay, or use alternate providers. Stop on denial or access block. Host independently verifies filtered-list coverage separately from fresh artifact and candidate-bound ordinary download, records actual tool events and exports BRAIN_RESULT.json and BRAIN_HANDOFF.json. Return DOWNLOAD_INITIATED after successful ordinary download action; only Host verifies file. Do not claim download success on a tool error. No file/shell calls to write reports. Aim for <=8 MCP outcomes and <=75s acquisition as targets only; never sacrifice correct match to speed. Return compact final JSON even on failure: status (DOWNLOAD_INITIATED, NO_PLAUSIBLE_CANDIDATE, ACCESS_BLOCKED, AUTH_REQUIRED, DOWNLOAD_FAILED, TOOL_UNAVAILABLE, UNKNOWN), observed_evidence, release_match (EXACT_METADATA, EVIDENCED_COMPATIBLE, UNKNOWN, CONFLICT), compatibility_uncertainties, actions (actual actions with ordinal, tool, purpose, result, error, decision), reusable_recipe (ordered brief steps without candidate IDs, local paths or subtitle text), recipe_codes (ordered array only from LIST_TASK_TAB, NAVIGATE_PROVIDER, QUERY_TITLE_YEAR, FILTER_ENGLISH, MATCH_RELEASE, CHECK_DETAIL, BIND_CANDIDATE, DOWNLOAD_ONCE, COMPACT_DOM, AVOID_REPEAT_SNAPSHOT, STOP_ON_DENIAL, MARK_UNKNOWN_METADATA, CHECK_TIMELINE, HOST_VERIFY_FILE, FINAL_REPORT), failures, improvements, usage if exposed. Report observations and evidence from this run only. Keep final JSON compact (roughly 1500-2500 characters if feasible); preserve decision and uncertainty. Concise operational decisions only; no hidden reasoning. No translation, TV or production effects. Input metadata: "
# Compact recipe; list coverage is observational, not an acceptance gate.
RECIPE_V13_4 = "Student Recipe V13.4 Compact. Find one compatible English subtitle for the exact film on OpenSubtitles.org using only the authorized ttv-browser MCP Chrome CDP 9555 tab. Use list_pages, select_page, navigate_page, evaluate_script, take_snapshot, click, fill, press_key, wait_for only; numeric pageId on page actions. No file/shell, guessed URLs, APIs, alternate providers, remembered candidate IDs, login/payment, or bypass. Stop on access denial. Aim <=8 outcomes and <=75s, not hard limits.\n\n1. List task tab once; start at ordinary https://www.opensubtitles.org/ search. One bounded DOM read of current visible search/filter controls (hints #search_text, #search_submit). Search dynamic title+year; select English if available. Verify actual result URL contains sublanguageid-eng and heading shows English. If mixed, follow actual visible English filter.\n2. Each actual result page: one compact evaluate_script returning {url,heading,page_title,total_english,count_scope,count_label,has_next,next_href,rows:[{href,lang,title,release,fps,badges,release_group,hi}]}. page_title is actual document.title; only its scoped \"English | N subtitles\" count qualifies: count_scope=filtered_results, count_label=page_title, total_english=N; else null/unknown. Read sufficient eligible English rows to select a compatible candidate; inspect further genuine pages only if useful; has_next means enabled visible forward link for this film/filter, next_href actual resolved href or null. Exclude unrelated/disabled navigation. Do not guess counts; incomplete coverage is permitted and reported, not a reason to stop. Read full release text/title attribute, actual row FPS, badge title/alt, explicit group and HI; unknown stays unknown. If a row language is blank, keep it blank; the verified English filter and the selected detail page's actual English title/language URL can corroborate it. Never invent a row language. No whole DOM/subtitle dumps or repeated reads.\n3. Rank by correct movie/year/cut, runtime/timing compatibility, completeness and trusted evidence, not encoding similarity, membership, popularity or count. Inspect strongest candidate with one bounded detail query: {url,candidate_id,title,btnVisible,fieldsetText,downloadHref,downloaderChecked}; fieldsetText from actual candidate-specific detail box around ordinary #bt-dwl-bt (release alternatives, runtime/FPS, language, notes, file type). downloaderChecked boolean or null if absent. Inspect other candidates only if material uncertainty changes choice. RIFE interpolated FPS can preserve timestamps; nominal FPS, WEB/BluRay, group, resolution or codec alone do not prove drift. Explicit cut/runtime conflict disqualifies; do not rescale without evidence. Prefer supported runtime/complete dialogue over unknown runtime with closer encoding; non-HI tiebreaker.\n4. Bind selected detail ID to visible ordinary Download #bt-dwl-bt (not beta/preview/installer). If optional downloader is checked, uncheck via ordinary UI. In final bounded evaluate_script recheck ID, visible ordinary href, checkbox false/null; click once and return {clicked:true,pageUrl,href,id,downloaderChecked}. Otherwise stop and report mismatch. Stop browser actions after click. Host independently verifies selected English row, candidate detail/click binding, fresh artifact and SRT; click alone is not download success.\n5. Return compact JSON: status (DOWNLOAD_INITIATED, NO_PLAUSIBLE_CANDIDATE, ACCESS_BLOCKED, AUTH_REQUIRED, DOWNLOAD_FAILED, TOOL_UNAVAILABLE, UNKNOWN), observed_evidence, release_match (EXACT_METADATA, EVIDENCED_COMPATIBLE, UNKNOWN, CONFLICT), compatibility_uncertainties, actions (ordinal, tool, purpose, result, error, decision), reusable_recipe, recipe_codes (LIST_TASK_TAB, NAVIGATE_PROVIDER, QUERY_TITLE_YEAR, FILTER_ENGLISH, MATCH_RELEASE, CHECK_DETAIL, BIND_CANDIDATE, DOWNLOAD_ONCE, COMPACT_DOM, AVOID_REPEAT_SNAPSHOT, STOP_ON_DENIAL, MARK_UNKNOWN_METADATA, CHECK_TIMELINE, HOST_VERIFY_FILE, FINAL_REPORT), failures, improvements, usage if exposed. Actual observations only; omit repeated narrative, no hidden reasoning, no extra tools for reporting. No translation, TV or production effects. Input metadata: "

# Prompt-only speed candidate. The independent verifier and retained cache revision are unchanged.
RECIPE = "Student Recipe V13.5 Fast. Find one compatible English SRT for the exact film on OpenSubtitles.org, using only authorized ttv-browser MCP CDP 9555 (numeric pageId). Only list_pages, select_page, navigate_page, evaluate_script, take_snapshot, click, fill, press_key, wait_for. No guessed URLs, APIs, other providers, remembered IDs, file/shell, login/payment or bypass; stop on denial.\n\nFast path (aim 6-8 outcomes, 30-50s; never trade correctness for speed):\n1. List the single task tab once. Navigate to ordinary https://www.opensubtitles.org/ only if not already on its search page. In one bounded evaluate_script, inspect actual visible search/filter controls (#search_text, #search_submit hints); if clear, fill title+year, select English and submit using ordinary UI in that same action. If unclear, inspect only what's missing.\n2. On actual result page, verify URL sublanguageid-eng and English heading; otherwise follow the visible English filter. One compact DOM read returns {url,heading,page_title,total_english,count_scope,count_label,has_next,next_href,rows:[{href,lang,title,release,fps,badges,release_group,hi}]}. Use actual document.title as page_title, scoped English | N subtitles only for filtered_results count, otherwise null/unknown; next_href actual enabled same-film/filter next link or null. Read sufficient eligible rows, full release text/title attribute, actual FPS/badges/group/HI; blank language stays blank. No exhaustive scan required. Further pages only for material uncertainty.\n3. Rank correct title/year/cut, runtime/timing and completeness ahead of encoding, membership or popularity. Navigate to strongest row's actual href. One detail read returns {url,candidate_id,title,btnVisible,fieldsetText,downloadHref,downloaderChecked} from actual ordinary #bt-dwl-bt candidate detail (release notes/alternatives, runtime/FPS, language, file type). Explicit runtime/cut conflict disqualifies; unknown remains unknown. RIFE interpolated FPS can preserve original timestamps; nominal FPS or encoding difference alone doesn't prove drift; no retiming. Inspect another only if it could change the choice; non-HI tiebreaker.\n4. Use ordinary UI to uncheck optional downloader if checked. In one final bounded evaluate_script recheck candidate ID, visible ordinary #bt-dwl-bt href, checkbox false/null; click once (not beta/preview/installer) and return {clicked:true,pageUrl,href,id,downloaderChecked}. Otherwise stop. Stop browser actions after click. Host verifies actual artifact, English, identity, candidate binding and timeline.\n5. Return ONLY compact JSON {status,release_match,compatibility_uncertainties}; status one of DOWNLOAD_INITIATED, NO_PLAUSIBLE_CANDIDATE, ACCESS_BLOCKED, AUTH_REQUIRED, DOWNLOAD_FAILED, TOOL_UNAVAILABLE, UNKNOWN; release_match EXACT_METADATA/EVIDENCED_COMPATIBLE/UNKNOWN/CONFLICT. Report actual observations only, brief uncertainty, no repeated action list, recipe, prose or extra reporting tools. Click is not download success. No translation or TV effects. Input metadata: "

def filter_gate(outputs,artifacts):
    def url(v):
        if not isinstance(v,str) or not v:return None
        try:u=urllib.parse.urlsplit(urllib.parse.urljoin("https://www.opensubtitles.org/",v))
        except ValueError:return None
        return u if u.scheme=="https" and u.hostname in (os_hosts|{"dl.opensubtitles.org"}) else None
    def sid(v):
        u=url(v)
        m=re.search(r"/(?:subtitles|download/sub|subtitleserve/sub)/(\d+)(?:/|$)",u.path) if u else None
        return m[1] if m else ""
    def lang_en(v):
        return isinstance(v,str) and " ".join(v.casefold().split()) in {"english","en","eng","flag en"}
    def language_state(v):
        if v is None or (isinstance(v,str) and v.strip().casefold() in {"","unknown","null","n/a"}):
            return "unknown"
        return "english" if lang_en(v) else "conflict"
    def english_detail(d):
        # First-party selected detail title + language-specific slug, not
        # a model's final claim. Only used with an English-filtered row.
        u=url(d.get("url"))
        return bool(u and u.hostname in os_hosts and
                    re.search(r"/subtitles/\d+/[^/]+-en/?$",u.path,re.I) and
                    isinstance(d.get("title"),str) and re.search(r"\benglish\b",d["title"],re.I))
    def docs(v):
        if isinstance(v,dict):return [v]
        if not isinstance(v,str):return []
        blocks=re.findall(r"(?s)\x60\x60\x60(?:json)?\s*(\{.*?\})\s*\x60\x60\x60",v) or [v.strip()]
        result=[]
        for block in blocks:
            try:x=json.loads(block)
            except (ValueError,TypeError):continue
            if isinstance(x,dict):result.append(x)
        return result
    groups={};details={};detail_text={};clicks=[];selected_rows={}; non_english={};detail_english=set();detail_conflicts={}
    for out in outputs:
        if out.get("error") or out.get("tool")!="evaluate_script":continue
        for d in docs(out.get("output")):
            u=url(d.get("url"))
            event=out["event"]
            did=sid(d.get("url"))
            if did and d.get("btnVisible") is True and isinstance(d.get("fieldsetText"),str) and d["fieldsetText"] and sid(d.get("downloadHref"))==did:
                details.setdefault(did,[]).append(event)
                detail_text[(did,event)]=d["fieldsetText"]
                if english_detail(d):detail_english.add((did,event))
                if any(language_state(d.get(k))=="conflict" for k in ("lang","language","language_code","languageCode")):
                    detail_conflicts.setdefault(did,[]).append(event)
            if d.get("clicked") is True:
                cid=sid(d.get("pageUrl"))
                if cid and str(d.get("id"))==cid and sid(d.get("href"))==cid and "downloaderChecked" in d and d["downloaderChecked"] in (False,None):
                    clicks.append((cid,event,d["pageUrl"]))
            if not u:continue
            heading=str(d.get("heading",""))
            filtered=bool(re.search(r"(?:^|/)sublanguageid-eng(?:/|$)",u.path) and re.search(r"\benglish\b",heading,re.I))
            total=d.get("total_english"); rows=d.get("rows"); nxt=d.get("has_next")
            # Row provenance is independent of page count/pagination reporting.
            # English language is a result property. A blank row field is
            # not a contradictory language when independent page evidence agrees.
            if u.hostname in os_hosts and re.search(r"(?:^|/)search(?:/|$)",u.path) and isinstance(rows,list):
                for row in rows:
                    if not isinstance(row,dict):continue
                    rid=sid(row.get("href"))
                    if not rid:continue
                    observed=[row.get(k) for k in ("lang","language","language_code","languageCode")]
                    states={language_state(v) for v in observed}
                    release=row.get("release")
                    if "conflict" in states:
                        non_english.setdefault(rid,[]).append(event)
                        continue
                    explicit=any(isinstance(v,str) and " ".join(v.casefold().split()) in {"english","en","eng"} for v in observed)
                    row_en=explicit or (filtered and "english" in states)
                    contextual=filtered and states=={"unknown"}
                    if (row_en or contextual) and isinstance(release,str) and release.strip().casefold() not in ("","unknown","null"):
                        selected_rows.setdefault(rid,[]).append((event," ".join(release.casefold().split()),row_en))
            if not filtered:continue
            if type(nxt) is not bool or not isinstance(rows,list) or not rows:continue
            found={sid(x.get("href")) for x in rows if isinstance(x,dict) and lang_en(x.get("lang"))}-{""}
            if len(found)!=len(rows):continue
            key=re.sub(r"/offset-\d+","",u.path)
            g=groups.setdefault(key,{"ids":set(),"totals":set(),"last":False,"events":[],"bad_count":False,"release_groups":{},"release_labels":{},"pagination_reports":[]})
            g["ids"].update(found);g["last"]|=not nxt;g["events"].append(event);g["pagination_reports"].append({"event":event,"path":u.path,"has_next":nxt,"next_href":d.get("next_href")})
            for row in rows:
                if isinstance(row,dict) and isinstance(row.get("release"),str) and row["release"].strip().casefold() not in ("","unknown","null"):
                    g["release_labels"][sid(row.get("href"))]=" ".join(row["release"].casefold().split())
                if isinstance(row,dict) and isinstance(row.get("release_group"),str) and row["release_group"].strip().casefold() not in ("","unknown","null"):
                    g["release_groups"][sid(row.get("href"))]=row["release_group"].strip().casefold()
            page_title=d.get("page_title")
            match=re.search(r"\bEnglish\s*\|\s*(\d+)\s+subtitles?\s*$",page_title,re.I) if isinstance(page_title,str) else None
            if type(total) is int and 0<total<=500 and match and int(match[1])==total and d.get("count_scope")=="filtered_results" and d.get("count_label")==page_title:g["totals"].add(total)
            else:g["bad_count"]=True
    count_matched=[g for g in groups.values() if not g["bad_count"] and g["totals"]=={len(g["ids"])}]
    def consistent_pages(g):
        # Count equality alone does not resolve contradictory pagination.
        # Require one terminal and a complete, acyclic observed next-link chain.
        pages={}
        for row in g["pagination_reports"]:
            path=row["path"]; nxt=row["has_next"]; href=row["next_href"]
            target=url(href) if href else None
            if nxt and (not target or target.path==path):
                return False
            if not nxt and href:
                return False
            edge=target.path if target else None
            if path in pages and pages[path]!=edge:
                return False
            pages[path]=edge
        targets={x for x in pages.values() if x is not None}
        if not targets.issubset(pages) or list(pages.values()).count(None)!=1:
            return False
        starts=set(pages)-targets
        if len(starts)!=1:
            return False
        current=next(iter(starts)); seen=set()
        while current is not None:
            if current in seen:
                return False
            seen.add(current);current=pages[current]
        return seen==set(pages)
    complete=[g for g in count_matched if g["last"] and consistent_pages(g)]
    count_ok=len(count_matched)==1
    list_ok=len(complete)==1
    chosen="";chosen_release="";chosen_page="";click_ok=False;selected_list_ok=False;compared_groups=0;compared_details=0;compared_labels=0;missing_group=0
    chosen_details=[]; release_rows={}; compared_ids=set()
    if len(clicks)==1:
        chosen,event,chosen_page=clicks[0]
        matching=[g for g in groups.values() if chosen in g["ids"] and any(max(g["events"])<x<event for x in details.get(chosen,[]))]
        click_ok=len(matching)==1
        if click_ok:
            group=matching[0]
            selected_list_ok=any(group is g for g in complete)
            chosen_release=group["release_labels"].get(chosen,"")
            eligible={candidate for candidate,events in details.items() if candidate in group["ids"] and any(max(group["events"])<x<event for x in events)}
            chosen_details=[detail_text[(chosen,x)] for x in details[chosen] if max(group["events"])<x<event]
            release_rows={candidate:{"release":label,"group":group["release_groups"].get(candidate)} for candidate,label in group["release_labels"].items()}
            compared_ids=eligible
            compared_details=len(eligible)
            compared_groups=len({group["release_groups"][candidate] for candidate in eligible if candidate in group["release_groups"]})
            compared_labels=len({group["release_labels"][candidate] for candidate in eligible if candidate in group["release_labels"]})
            missing_group=len(eligible-set(group["release_groups"]))
    # Bind the one chosen English row to an observed detail and ordinary click.
    # No exhaustive scan, total count, terminal page or unique search group required.
    click_ok=False;chosen_release="";chosen_details=[]
    if len(clicks)==1:
        chosen,event,chosen_page=clicks[0]
        rows=[(e,label,en) for e,label,en in selected_rows.get(chosen,[]) if e<event]
        labels={label for e,label,en in rows}
        if (len(labels)==1 and not any(e<event for e in non_english.get(chosen,[]))
                and not any(e<event for e in detail_conflicts.get(chosen,[]))):
            detail_events=[x for x in details.get(chosen,[]) if x<event]
            # Accept independently observed row and detail in either order.
            # For blank row language require corroboration from the selected
            # first-party detail, in addition to the English filtered page.
            language_ok=any(en for e,label,en in rows) or any((chosen,x) in detail_english for x in detail_events)
            chosen_details=[detail_text[(chosen,x)] for x in detail_events]
            click_ok=bool(chosen_details and language_ok)
            if click_ok:chosen_release=next(iter(labels))
    ids={sid(x) for x in artifacts[0].get("candidate_refs",[])}-{""} if len(artifacts)==1 and artifacts[0].get("copied_to_job") is True else set()
    download_ok=bool(click_ok and ids=={chosen})
    return {"accepted":download_ok,"reason":"SELECTED_ENGLISH_AND_DOWNLOAD_BOUND" if download_ok else "DOWNLOAD_UNVERIFIED" if click_ok else "SELECTED_CANDIDATE_UNBOUND","chosen_candidate":chosen,"chosen_release":chosen_release,"chosen_page":chosen_page,"selected_list_verified":selected_list_ok,"english_list_verified":list_ok,"scoped_count_matches_unique_rows":count_ok,"pagination_terminal_verified":list_ok,"english_candidates":len(complete[0]["ids"]) if list_ok else 0,"english_rows_observed":len(next(iter(groups.values()))["ids"]) if len(groups)==1 else 0,"ordinary_click_bound":click_ok,"download_verified":download_ok,"detail_candidates":len(details),"distinct_release_groups_compared":compared_groups,"candidate_details_compared_before_click":compared_details,"distinct_observed_release_labels_compared":compared_labels,"compared_candidates_missing_group":missing_group,"release_compatibility_verified":False,"chosen_detail_texts":chosen_details,"release_rows":release_rows,"compared_candidate_ids":sorted(compared_ids)}

@dataclass(frozen=True)
class BrowserRequest:
    media: Media
    model: str = MODEL
    thinking_level: str = THINKING_LEVEL

    def prompt(self, *, duration_seconds: float, fps: float) -> str:
        if not _valid_probe(duration_seconds, fps):
            raise AgyEnglishUnavailable("AGY_EN_VIDEO_PROBE_REQUIRED")
        release = preferred_media_release(self.media)
        # Exact identity remains local. Only release hints reach AGY.
        return RECIPE + json.dumps({
            "title": release.title, "year": release.year,
            "release": self.media.torrent_title or self.media.filename,
            "release_origin": "TORRSERVER_VERIFIED",
            "duration": duration_seconds, "duration_unit": "seconds",
            "fps": fps,
        }, ensure_ascii=True)


@dataclass(frozen=True)
class BrowserEvidence:
    """Produced from the Owner's observed job, never from model assertions."""
    media: Media
    duration_seconds: float
    fps: float
    outcomes: tuple[dict, ...]
    artifacts: tuple[dict, ...]
    download_bytes: bytes
    # True only if the native producer independently observed a fresh download
    # tied to its unique invocation; not a field supplied by the model.
    fresh_download_verified: bool


NativeRunner = Callable[[BrowserRequest, Path], BrowserEvidence]


def _valid_probe(duration, fps):
    return (type(duration) in (int, float) and type(fps) in (int, float)
            and math.isfinite(duration) and math.isfinite(fps)
            and 0 < duration <= 86400 and 0 < fps <= 240)


def _subtitle_bytes(blob: bytes) -> bytes:
    if not isinstance(blob, bytes) or not 0 < len(blob) <= MAX_DOWNLOAD_BYTES:
        raise AgyEnglishUnavailable("AGY_EN_ARTIFACT_MISSING_OR_UNSAFE")
    if blob.startswith(b"PK"):
        try:
            with zipfile.ZipFile(io.BytesIO(blob)) as z:
                members = [x for x in z.infolist() if not x.is_dir()]
                entries = [x for x in members if x.filename.lower().endswith(".srt")]
                if (len(members) > 100 or len(entries) != 1
                        or not 0 < entries[0].file_size <= MAX_SUBTITLE_BYTES
                        or entries[0].flag_bits & 1):
                    raise AgyEnglishUnavailable("AGY_EN_ARTIFACT_AMBIGUOUS")
                # Read one bounded entry into memory; never extract paths.
                with z.open(entries[0]) as f:
                    return f.read(MAX_SUBTITLE_BYTES + 1)
        except (ValueError, RuntimeError, OSError, zipfile.BadZipFile, NotImplementedError):
            raise AgyEnglishUnavailable("AGY_EN_ARTIFACT_INVALID") from None
    return blob


def _check_selected_movie(media, release):
    """AGY chooses the cut; Owner verifies film identity, not encoding similarity.

    Unknown runtime/FPS are not synchronization proof. Explicit conflicts and
    invalid SRT remain rejected by the separate timeline checks.
    """
    target = preferred_media_release(media)
    selected = parse_release(release)
    if (not target.title or not selected.title
            or target.title.removeprefix("the ") != selected.title.removeprefix("the ")
            or (target.year is not None and target.year != selected.year)):
        raise AgyEnglishUnavailable("AGY_EN_MEDIA_RELEASE_MISMATCH")


def _check_selected_runtime(gate, duration):
    """Validate explicit runtime for the chosen release, not the search method."""
    # Only labelled HH:MM:SS / minute metadata is interpretable. A minute
    # precision allowance avoids rejecting ordinary rounded site metadata.
    for text in gate["chosen_detail_texts"]:
        for match in re.finditer(r"(?im)^\s*(?:movie\s+)?(?:runtime|duration|length)\s*:\s*(\d{1,2}):([0-5]\d):([0-5]\d)\b", text):
            h,m,s=map(int,match.groups())
            if abs((h*3600+m*60+s)-duration)>60:
                raise AgyEnglishUnavailable("AGY_EN_EXPLICIT_RUNTIME_CONFLICT")
        for match in re.finditer(r"(?im)^\s*(?:movie\s+)?(?:runtime|duration|length)\s*:\s*(\d{1,4})\s*(?:minutes?|mins?)\b", text):
            if abs(int(match.group(1))*60-duration)>60:
                raise AgyEnglishUnavailable("AGY_EN_EXPLICIT_RUNTIME_CONFLICT")


def timeline_observation(contents, duration):
    """Measured subtitle span, not a dialogue-completeness verdict."""
    from opensubtitles import _milliseconds
    text = contents.decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    starts=[]; ends=[]
    for block in re.split(r"\n[ \t]*\n", text.strip()):
        lines = [line.strip() for line in block.split("\n")]
        timing = next(line for line in lines[:2] if "-->" in line)
        left,right=timing.split("-->",1)
        starts.append(_milliseconds(left.strip(),"srt"))
        ends.append(_milliseconds(right.strip().split(" ",1)[0],"srt"))
    return {"first_cue_ms":min(starts),"last_cue_ms":max(ends),
            "cues":len(starts),"first_10m_cues":sum(t<600000 for t in starts),
            "timeline_span_fraction":round((max(ends)-min(starts))/(duration*1000),6),
            "dialogue_completeness":"UNVERIFIED","sync":"UNVERIFIED"}


def verify_evidence(request: BrowserRequest, proof: BrowserEvidence) -> Asset:
    if not isinstance(proof, BrowserEvidence) or proof.media != request.media:
        raise AgyEnglishUnavailable("AGY_EN_MEDIA_BINDING_MISMATCH")
    if not _valid_probe(proof.duration_seconds, proof.fps):
        raise AgyEnglishUnavailable("AGY_EN_VIDEO_PROBE_REQUIRED")
    if (proof.fresh_download_verified is not True
            or not isinstance(proof.download_bytes, bytes)
            or not 0 < len(proof.download_bytes) <= MAX_DOWNLOAD_BYTES
            or len(proof.artifacts) != 1 or not isinstance(proof.artifacts[0], dict)):
        raise AgyEnglishUnavailable("AGY_EN_ARTIFACT_UNVERIFIED")
    a = proof.artifacts[0]
    if (a.get("sha256") != hashlib.sha256(proof.download_bytes).hexdigest()
            or a.get("bytes") != len(proof.download_bytes)):
        raise AgyEnglishUnavailable("AGY_EN_ARTIFACT_HASH_MISMATCH")
    try:
        gate = filter_gate(proof.outcomes, proof.artifacts)
    except (TypeError, ValueError, KeyError, AttributeError):
        raise AgyEnglishUnavailable("AGY_EN_EVIDENCE_INVALID") from None
    if not gate["accepted"] or not gate["chosen_release"]:
        raise AgyEnglishUnavailable("AGY_EN_" + gate["reason"]
                                    if not gate["accepted"] else "AGY_EN_RELEASE_UNOBSERVED")
    # The selected candidate's observed download remains bound above.
    # Encoding metadata (group/source/resolution/codec) is not a cut proof.
    _check_selected_movie(request.media, gate["chosen_release"])
    _check_selected_runtime(gate, proof.duration_seconds)
    contents = _subtitle_bytes(proof.download_bytes)
    try:
        count = validate_timed_text(contents, "srt")
    except SubtitleApiError:
        raise AgyEnglishUnavailable("AGY_EN_ARTIFACT_TIMELINE_INVALID") from None
    # Reject impossible overrun (2s allowance for container rounding/outro).
    # This sanity bound is not evidence of dialogue alignment or completeness.
    observation = timeline_observation(contents, proof.duration_seconds)
    if observation["last_cue_ms"] > (proof.duration_seconds + 2) * 1000:
        raise AgyEnglishUnavailable("AGY_EN_ARTIFACT_OVERRUN")
    # A valid SRT is not proof of exact playback synchronization.
    return Asset(0, "en", "srt", contents, hashlib.sha256(contents).hexdigest(), count)


def make_v13_acquirer(runner: NativeRunner) -> Callable[[Media, Path], Asset]:
    """One injected native invocation; no fallback to API or second provider."""
    if not callable(runner):
        raise ValueError("AUTO_AGY_NATIVE_RUNNER_INVALID")

    def acquire(media: Media, cache_root: Path) -> Asset:
        request = BrowserRequest(media)
        return verify_evidence(request, runner(request, cache_root))

    acquire.native_v13 = True
    return acquire
