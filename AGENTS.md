# AGENTS

Small local ICS calendar editor.

## Version stamp

The top-right `🎋` version stamp comes from a hardcoded `VERSION` string in
`icswebedit` using the format `YYYY-MM-DD-HH` and reflects the last shipped
code change. Only bump it when shipped code changes.

## Run

You need `pipx`.

Run the webserver with:

```sh
pipx run ./icswebedit /path/to/calendar.ics
```
