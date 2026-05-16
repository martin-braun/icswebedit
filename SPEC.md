# SPEC — `icswebedit`

## Goal

Implement a small single-file Python web application named `icswebedit` that is
run by `pipx run`.

It edits one local `.ics` file through a browser UI.

The intended user is non-technical. The app must be launchable from a macOS
Shortcut, but the Python script itself must be cross-platform and work on macOS,
Linux, and Windows. The repository includes macOS Shortcut setup instructions in
`README.md`.

Do **not** build a Cocoa app.\
Do **not** build a Qt app.\
Do **not** build or require a CalDAV server.\
Do **not** use `icalcli`.\
Do **not** use Flask/Django/FastAPI unless explicitly approved later. Use Python
stdlib `http.server`.

The `.ics` file remains the source of truth.

---

## Repository helper docs

The repository includes a very basic `AGENTS.md` and a human-facing
`README.md`, which contains the macOS Shortcut and Dock setup notes. There is
no separate `shortcuts/README.md`.

It:

- describe the project in very few words
- say that `pipx` is needed
- show how to run the webserver with `pipx run ./icswebedit /path/to/calendar.ics`
- not instruct using `python3`

The `README.md` should:

- explain the project for human readers
- include a prominent disclaimer that the project was vibe coded by the
  assistant and should be reviewed and tested carefully
- explain basic usage and data-safety expectations
- include the macOS Shortcut and Dock setup instructions

Repository documentation examples should use generic placeholder values rather
than user-specific usernames, paths, or machine-local details.

---

## File name

The script must be named:

```text
icswebedit
```

It should be executable.

---

## Script header

Use this exact style of header, with only the dependencies needed by this app:

```py
#!/usr/bin/env -S pipx run
# pyright: reportMissingModuleSource=false, reportMissingImports=false
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "icalendar<8",
#     "recurring-ical-events<4",
# ]
# ///
```

No other third-party dependencies are allowed unless the implementation
absolutely requires them.

Use only stdlib for the webserver, routing, JSON, HTML escaping, temp files,
path handling, UUID generation, and date/time helpers.

---

## CLI contract

```sh
icswebedit /path/to/calendar.ics [port]
```

Arguments:

1. First argument: required path to the `.ics` file.
2. Second argument: optional port.

Behavior:

- Bind only to `127.0.0.1`.
- Default port: `8765`.
- If a port is explicitly provided and unavailable, fail with a clear error.
- After the server is ready, print a listening message with exactly one URL to
  stdout and flush:

```text
Listening on http://127.0.0.1:8765/
```

Use the actual selected port.

After printing the listening message, continue serving forever until the
process is killed or the user presses an Exit button in the UI.

Do not open the browser from Python. The macOS Shortcut opens the website.

Do not print request logs to stdout. Suppress default `http.server` request
logging.

Errors may go to stderr.

---

## macOS Shortcut contract

The repository documents the Shortcut setup in `README.md` rather than in a
separate `shortcuts/README.md` or a standalone `.sh` launcher file.

All hardcoded Shortcut values shown in the repository are generic examples and
should be treated as placeholders for the user's actual calendar path and
chosen port.

The Shortcut should hardcode:

```sh
SCRIPT="$HOME/.sources/github.com/example/icswebedit/icswebedit"
ICS="$HOME/Calendars/personal-calendar.ics"
PORT=8765
URL="http://127.0.0.1:$PORT/"
```

The Shortcut should:

1. Start the repository's executable `icswebedit` script by absolute path in the
   background.
2. Open `$URL` in the default browser.
3. Never show Terminal to the user.
4. Be suitable for the Shortcuts app's **Add to Dock** flow so the user gets a
   Dock icon.

Example shell logic for the Shortcut's **Run Shell Script** action:

```sh
SCRIPT="$HOME/.sources/github.com/example/icswebedit/icswebedit"
ICS="$HOME/Calendars/personal-calendar.ics"
PORT=8765
URL="http://127.0.0.1:$PORT/"

if ! nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then
    nohup "$SCRIPT" "$ICS" "$PORT" >/dev/null 2>%1 &
    sleep 1
fi

open "$URL"  
```

This shell snippet is for the Shortcut only. The Python script must stay
cross-platform. The repository does not ship this as a standalone `.sh` file.

---

## Session and file model

On startup:

1. Validate the `.ics` path.
2. If the file does not exist, create an in-memory empty calendar:

```ics
BEGIN:VCALENDAR
END:VCALENDAR
```

3. Create a temporary session file in the OS temp directory using Python's
   `tempfile` module.
4. The temp filename must be a real generated temp path, equivalent in spirit to
   the output of `mktemp`.
5. The temp file must **not** live in the same directory as the original `.ics`.
6. Copy or serialize the initial calendar into that temp file.
7. All browser edits modify the temp session file, not the original `.ics`.

While the server process is alive:

- Reloading/reopening the website uses the current temp session file.
- It must not re-read the original `.ics` after startup.
- The temp file represents the current unsaved session.

On Save:

1. Serialize the temp session calendar.
2. Automatically delete past non-recurring events before writing, so the file
   stays tidy and does not grow forever.
3. Create a backup of the old original `.ics` before replacing it.
4. Write to a staging file in the original `.ics` directory.
5. Flush and `fsync` the staging file.
6. Replace the original atomically using `os.replace`.
7. `fsync` the parent directory where supported.
8. Keep the temp session active after saving.

Recurring events are never auto-deleted during Save.

Backup filename:

```text
.sample_YYYYMMDD-HHMMSS.ics
```

Example:

```text
.personal-calendar_20260514-153012.ics
```

Use system time for the backup filename. The backup name must start with a dot
and use the original file stem plus `_YYYYMMDD-HHMMSS.ics`.

If the original file did not exist before Save, skip the backup.

On Exit:

- Stop the server.
- Keep the original `.ics` untouched unless Save was pressed.
- Delete the temp session file if possible.

Keep only `POST /exit` for this action; do not keep legacy `/quit`,
`/reset`, or `/discard` aliases.

No file locking is required.

---

## Core behavior

The app edits only future events.

Definitions:

- `now` is the user's local current time, but any stored times in the `ics` file are in UTC
- One-off timed event is editable/deletable if its effective end time is
  `>= now`.
- One-off all-day event is editable/deletable if its date is today or later.
- All recurring events are editable/deletable, but they affect all events.

> We do not allow to edit single events of a recurring event to keep it simple (no splitting of the events).

---

## Recurring events rule

Do not generate `RECURRENCE-ID` exceptions for edits.

Do not generate `EXDATE` for deletes.

Because recurrence is configured through a simple frequency dropdown, this tool
does not support `COUNT` for recurring events. Users are expected to delete old
recurring series themselves when they are no longer needed.

The bundled `example.ics` and `sample.ics` should therefore avoid `;COUNT=*`
rules so their recurring events stay open-ended and keep showing up as next-due
occurrences until the user deletes the stale series.

If a recurring event is editted, edit the stored `VEVENT` as one whole
component, exactly as the ICS file stores it.

If a recurring event is deletable, delete the stored `VEVENT` as one whole
component.

In the UI, recurring events should be labeled clearly:

```text
Repeating event — edits affect the whole stored series
```

For v1, it is acceptable to make recurring events read-only except for
future-starting recurring series.

---

## Timezone rules

Display all timed events in the browser's local timezone.

Store all created or modified timed events in UTC:

```ics
DTSTART:20260520T064500Z
DTEND:20260520T073000Z
```

Do not store modified timed events with `TZID`.

Use UTC internally for timed event payloads sent between browser and server.

Browser-side behavior:

- Use JavaScript `Date` to convert UTC timestamps to the browser's local display
  time.
- Use `<input type="datetime-local">` for editing local wall time.
- Convert local form values back to UTC ISO strings before sending them to the
  server.

Server-side behavior:

- Accept UTC ISO strings from the browser.
- Write UTC-aware Python `datetime` values.
- Use `datetime.UTC`.
- For existing events with `TZID`, convert to UTC for API responses.
- For modified existing timed events, rewrite `DTSTART`/`DTEND` in UTC.

All-day events:

- All-day events use `DATE`, not UTC datetimes.
- Do not shift all-day dates through UTC conversion.
- Display all-day events as dates.
- If all-day editing is implemented, preserve them as `DATE`, with an inclusive
  end date in the form/UI that is converted back to the correct ICS-exclusive
  end date on write.

If all-day editing is not implemented in v1, display all-day events read-only.

---

## Required UI

Use a simple browser UI with embedded HTML/CSS/JS.

No external CDN.\
No external JavaScript packages.\
No build step.

Minimum pages/features:

### Home page `/`

Show:

- App title.
- A simple hour-based version stamp shown with `🎋` on the same row as the path,
  in the format `YYYY-MM-DD-HH`.
- Source `.ics` path shown as a folder emoji plus the path, without a `Source file:` prefix.
- Save button.
- Add Event button.
- Exit button.
- A large live digital clock above the future-events heading, shown with `🕒`
  and auto-updated every second using the browser's local date/time format.
- Event list for all future events.

The home page exposes a single exit-style action only; it does not need separate
Reset, Quit, Stop, or Discard buttons.

The home page button order should be:

1. Add Event
2. Save
3. Exit

Use emoji-heavy labels in the UI.

Examples:

- all primary action buttons should use emoji-only labels
- the Add Event button should use `✏️➕`
- the Exit button should use `👋🚫`
- the Save button should use `💾 ‼️` when there are unsaved changes and `💾 ✅`
  when the session is saved
- opening an existing in-sync calendar should show the saved `💾 ✅` state
- do not show a separate unsaved-status badge if the Save button already shows that state
- the UI should follow the browser language automatically, without a language
  switcher menu
- form labels that use emoji should use the emoji alone without duplicate text
- the Location label should use a pin emoji only
- the all-day checkbox should use `🔆` with the checkbox placed tightly next to it
- normal buttons should use a light gray background
- the Exit button should use the same danger background as the delete control
- the edit-form back control should also use that same danger background
- read the system dark-mode preference on page load and render a dark theme when
  dark mode is active; no live theme switching is required during the session

Built-in UI translations are provided for:

- English
- German
- Spanish
- Dutch
- Italian
- French
- Portuguese
- Chinese
- Japanese
- Korean
- Russian
- Arabic
- Hindi

The event list should be grouped by local date.

Each event row should show:

```text
time range | summary | location | recurrence marker | edit/delete controls when allowed
```

Example:

```text
Wed 20 May 2026
10:00–10:30: Team sync
🔆 Parents visiting
```

The main event line should be fully bold.

If a recurring event notice is shown in the beige callout, show it only once and
do not also repeat the same text in the plain metadata line.

Use `❌` for the delete control.

For recurring events, show only the next due occurrence in the overview, while
edit/delete still target the stored series.

Overview cards should use compact spacing, including reduced bottom padding.

Past events must not be shown unless they are today and still ongoing.

### Add Event page `/new`

Required fields:

- Summary
- Start date/time
- Location
- Description

Optional fields:

- All-day checkbox
- Recurrence dropdown with `daily`, `weekly`, and `monthly`
- Alarm lead-time dropdown at the bottom of the form

Do not build a complex recurrence editor beyond the supported frequency
dropdown.

The alarm dropdown should offer these values:

- 0, 5, 10, 15, 20, 30, 45 minutes
- 1, 1:30, 2, 2:30, 3, 4, 6, 9, 12, 18 hours
- 1, 1.5, 2, 2.5, 3, 4, 5, 6 days
- 1 week

Validation:

- Summary is required.
- Start must be before end.
- Start must be in the future.
- Timed events require an explicit end date/time.
- For all-day events, the form/UI end date is inclusive, so the same start and
  end date means a one-day event, while the stored ICS value must still use the
  correct exclusive end date.
- Timed values sent to server must be UTC.
- After leaving the timed start input, the timed end input should default to
  start + 15 minutes when empty.
- Validate all core date/time and required fields.
- Alarm and recurrence inputs are optional dropdowns and do not require complex
  free-form validation.

### Edit Event page `/edit?id=...`

Show the current stored component fields.

For a recurring event, clearly show:

```text
This edits the whole stored recurring event, not only one occurrence.
```

Editable fields:

- Summary
- Start
- End
- Location
- Description
- Recurrence dropdown
- Alarm lead-time dropdown

Validation same as Add, including requiring an explicit end date/time for timed
events.

### Delete flow

Deletion must require confirmation.

Delete removes the stored `VEVENT` from the temp session only.

The original `.ics` is untouched until Save.

---

## HTTP endpoints

Use simple routes.

Required:

```text
GET  /
GET  /new
POST /new
GET  /edit?id=...
POST /edit?id=...
POST /delete
POST /save
POST /exit
GET  /api/events
GET  /health
```

`/api/events` should return all future non-recurring events and only the next
due occurrence for each recurring event.

Event JSON shape:

```json
{
  "id": "stable-component-id",
  "uid": "event-uid",
  "summary": "dentist appointment",
  "location": "",
  "description": "",
  "start_utc": "2026-05-20T06:45:00Z",
  "end_utc": "2026-05-20T07:30:00Z",
  "all_day": false,
  "recurring": false,
  "editable": true,
  "deletable": true
}
```

For recurring occurrences, include:

```json
{
  "occurrence_start_utc": "...",
  "occurrence_end_utc": "...",
  "source_id": "stable-component-id",
  "recurring": true
}
```

Do not expose raw filesystem paths in JSON except the source path already shown
in the local-only UI.

---

## Event identity

Every new event must have:

- `UID`
- `DTSTAMP`
- `CREATED`
- `LAST-MODIFIED`

Use UUID-based UIDs:

```text
uuid@icswebedit
```

Example:

```text
29d5c43e-95d0-4e76-8dd1-5ed270f66108@icswebedit
```

Existing events without `UID`:

- Generate a UID in the temp session.
- Mark the session as changed.
- Do not touch the original file until Save.

Internal component ID:

- Use a stable ID for UI routes.
- Prefer `UID`.
- If needed, disambiguate with an ordinal index.
- Do not rely on list position alone after edits.

---

## ICS parsing/writing

Use `icalendar`.

Parse:

```py
from icalendar import Calendar
cal = Calendar.from_ical(data)
```

Serialize:

```py
cal.to_ical()
```

Required calendar properties when creating a new calendar:

```text
VERSION:2.0
PRODID:-//icswebedit//EN
CALSCALE:GREGORIAN
```

When adding or editing a timed event:

- Write `DTSTART` as UTC datetime.
- Write `DTEND` as UTC datetime.
- Prefer `DTEND` over `DURATION`.
- Update `DTSTAMP`.
- Update `LAST-MODIFIED`.

When editing:

- Preserve unknown properties where possible.
- Preserve alarms (`VALARM`) where possible.
- Preserve unrelated components.
- Do not reorder components intentionally, though library serialization may
  normalize.

When deleting:

- Remove the stored `VEVENT` component from the temp calendar.
- Do not delete `VTIMEZONE` components in v1.

---

## Recurrence expansion

Use `recurring-ical-events` for recurring-event overview data.

Purpose:

- Derive only the next due occurrence for each recurring event for display/API
  purposes.
- Do not use expansion results as editable events.
- Map each expanded occurrence back to the stored source `VEVENT`.

Use a bounded future lookahead of about 25 years when finding the next
recurring occurrence.
- Use a sufficiently long lookahead window when expanding recurrence so future
  sample events such as Team sync are still surfaced in overview/API results.

Sort by occurrence start time.

---

## HTML safety

Escape all user-provided values before inserting them into HTML:

- summary
- location
- description
- RRULE
- path display

Use `html.escape`.

Reject or safely encode invalid form input.

No authentication is required because the server binds only to `127.0.0.1`.

---

## Cross-platform requirements

The Python script must work on:

- macOS
- Linux
- Windows

Use:

- `pathlib.Path`
- `tempfile`
- `os.replace`
- `shutil.copy2`
- `datetime`
- `zoneinfo` if needed
- `http.server`

Do not use:

- `/bin/sh` inside Python
- `mktemp` command inside Python
- `open` command inside Python
- `nc` inside Python
- AppleScript inside Python
- macOS-only APIs inside Python

The macOS Shortcut may use macOS-specific shell commands. The Python script may
not.

---

## Save semantics

The app has two separate states:

1. Temp session state.
2. Saved original file state.

Every add/edit/delete changes only the temp session.

The Home page must show save state via the Save button label itself:

```text
💾 ‼️
```

or:

```text
💾 ✅
```

Save writes the temp session to the original `.ics`.

If Save fails:

- Keep the temp session.
- Show the error.
- Do not destroy the backup.
- Do not delete the temp file.

If backup creation fails:

- Abort Save.
- Show the error.
- Do not replace the original.

---

## Minimal visual design

Keep UI simple.

Use one embedded stylesheet.

Prefer:

- large buttons
- readable font
- narrow centered layout
- grouped event list
- obvious Save button
- obvious save-state indicator on the Save button

Support reading the system dark-mode preference on initial page load and render a
dark theme when active; no live theme switching is required during the session.

No drag/drop required.

No calendar grid required.

---

## Non-goals

Do not implement:

- CalDAV
- sync logic
- user accounts
- authentication
- multiple calendars
- invite handling
- attendee management
- timezone database editor
- recurrence exception editor
- split recurring event
- edit only one occurrence
- drag/drop calendar
- notifications
- native tray/menu app
- Qt
- Cocoa
- Electron

---

## Manual acceptance test

Prepare a working sample calendar:

Run:

```sh
cp example.ics sample.ics
pipx run ./icswebedit sample.ics
```

Expected:

1. Script prints:

```text
Listening on http://127.0.0.1:8765/
```

2. Browser shows all future one-off events and only the next due occurrence for
   each recurring event, including future recurring sample entries such as Team
   sync.
3. Add a future event.
4. Confirm original `sample.ics` is unchanged before Save.
5. Press Save.
6. Confirm:
   - backup file exists
   - original file contains the new event
   - new/modified timed events are stored with UTC `Z`
7. Edit a one-off event.
8. Confirm `LAST-MODIFIED` changes.
9. Delete a one-off event.
10. Confirm delete affects temp only until Save.
11. Confirm recurring event edit affects the stored series, not a single
    expanded occurrence.
12. Confirm recurring event with past `DTSTART` but future occurrence is
    read-only.

---

The repository should include an `example.ics` file with varied future sample
events for manual testing.

That file should include a mix of:

- single timed events
- all-day events
- recurring weekly events
- recurring daily events
- recurring monthly events
- entries with different locations, descriptions, alarms, and transparency

## Implementation preference

Keep the implementation boring.

One file is preferred.

Suggested structure:

```py
# header

import ...

APP_NAME = "icswebedit"
DEFAULT_PORT = 8765
MAX_AUTO_PORT = 8799

class AppState:
    original_path: Path
    temp_path: Path
    calendar: Calendar
    dirty: bool

def main() -> int: ...
def load_calendar(path: Path) -> Calendar: ...
def write_temp(state: AppState) -> None: ...
def save_original(state: AppState) -> None: ...
def make_backup(path: Path) -> Path: ...
def atomic_replace(src: Path, dst: Path) -> None: ...
def list_events(state: AppState) -> list[dict]: ...
def add_event(state: AppState, form: dict) -> None: ...
def edit_event(state: AppState, event_id: str, form: dict) -> None: ...
def delete_event(state: AppState, event_id: str) -> None: ...
class Handler(BaseHTTPRequestHandler): ...
```

Prefer clarity over cleverness.
