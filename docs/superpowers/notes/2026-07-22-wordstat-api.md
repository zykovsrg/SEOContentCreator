# Wordstat API — Findings

Date: 2026-07-22

Status: blocked — needs a user decision before Task 10 (real client) can be written.

## Summary

There are two documented Wordstat APIs, and the one the user already holds a
token for appears to be deprecated at the network level, not just old in the
docs.

## API 1 — Legacy OAuth (`api.wordstat.yandex.net`)

This is the API the user has an existing OAuth token for.

- Documented base URL: `https://api.wordstat.yandex.net`
- Documented methods: `/v1/topRequests`, `/v1/dynamics`, `/v1/regions`, `/v1/getRegionsTree`
- Auth: `Authorization: Bearer <OAuth token>`
- Access process (per official docs): create a Yandex OAuth app, register a
  ClientId, then contact Yandex Direct support with username + ClientId to get
  approved. Manual approval, can take days.
- Documented quota (secondhand, not confirmed on an official page): roughly
  10 requests/second and 1000 requests/day.

**Live test result:** a real POST to `https://api.wordstat.yandex.net/v1/topRequests`
with the user's token failed at the TLS layer, before any HTTP response:

```
* Server certificate:
*  subject: C=RU; ST=Moscow; L=Moscow; O=YANDEX LLC; CN=wordstat.yandex.ru
*  start date: Apr  1 22:07:27 2026 GMT
*  expire date: Sep 30 20:59:59 2026 GMT
*  subjectAltName does not match host name api.wordstat.yandex.net
* SSL: no alternative certificate subject name matches target host name 'api.wordstat.yandex.net'
```

The hostname resolves and connects, but the certificate served is for
`wordstat.yandex.ru`, not `api.wordstat.yandex.net`. This does not look like a
local network problem — it looks like the `api.wordstat.yandex.net` endpoint no
longer has a matching certificate, consistent with Yandex having migrated the
service. The request was not retried with certificate verification disabled:
sending a real OAuth token over a connection that fails hostname verification
would risk the token being intercepted, so the app's future `WordstatClient`
must not do this either.

**Independent confirmation:** the current official documentation page
(`yandex.ru/support2/wordstat/ru/content/api-wordstat`) states plainly: "Все
возможности API Вордстата теперь доступны в Wordstat API" (all Wordstat API
capabilities are now available in [the new] Wordstat API), and links to
`yandex.cloud/ru/docs/search-api/concepts/wordstat`, which redirects to
`aistudio.yandex.ru/docs/ru/search-api/concepts/wordstat`. This points the same
direction as the TLS failure: the legacy endpoint is being phased out in favor
of the Cloud-based API below.

## API 2 — Yandex Cloud Search API (`searchapi.api.cloud.yandex.net`)

This is the currently-documented, self-service replacement. The user does not
yet have credentials for it.

- Base URL: `https://searchapi.api.cloud.yandex.net/v2/wordstat/`
- Methods: `/topRequests` (phrases + 30-day frequency), `/dynamics` (frequency
  over time), `/regions` (geographic distribution), `/getRegionsTree` (region
  reference; does not consume quota)
- Auth: `Authorization: Api-Key <key>` — the same kind of key used for
  YandexGPT in AI Studio, plus a required `folderId` (Yandex Cloud project
  identifier) in every request body.
- Access: self-service via Yandex Cloud console / AI Studio. No manual Direct
  approval reported.
- `topRequests` request body:
  ```json
  {"phrase": "string, up to 400 chars", "folderId": "string, required", "numPhrases": 20, "regions": ["213"], "devices": ["DEVICE_ALL"]}
  ```
- `topRequests` response body:
  ```json
  {"totalCount": "string", "results": [{"phrase": "string", "count": "string"}], "associations": [{"phrase": "string", "count": "string"}]}
  ```
  **`count` arrives as a string**, not a number — a documented consequence of
  gRPC int64 serialization. The parser must decode it as a numeric string and
  convert, not decode it as `Int` directly.
- Reported free-tier quota (from a third-party walkthrough, not an official
  page): on the order of 5-10 requests/second; a daily cap was not confirmed
  from an official source.
- Devices enum values seen in different sources disagree in casing
  (`"DEVICE_PHONE"` vs `"phone"`) — this needs one live test call to pin down,
  since only one source shows the enum-style values consistently across all
  four endpoints.

This second source could not be independently re-verified directly against the
official AI Studio docs pages: two fetch attempts against
`aistudio.yandex.ru/docs/...` both returned a Yandex CAPTCHA challenge page
instead of content, likely bot detection on automated fetches. The shape above
comes from a third-party technical walkthrough (Habr, dated 2026) that
described request/response bodies for all four methods in detail and is
internally consistent with the official migration notice above.

## Decision needed

Task 10 (the real Wordstat client) cannot be written correctly until one of
these is resolved:

1. The user obtains a Yandex Cloud API key + `folderId` and the plan targets
   API 2, or
2. The user confirms their existing OAuth token still works through some other
   channel (e.g., it succeeds in a tool that isn't blocked by TLS hostname
   verification, or Yandex support confirms the legacy host), and the plan
   targets API 1, or
3. The user decides to pause Wordstat integration and have Task 10 build
   against a fixture-only fake for now, with the real client done in a follow-up
   once credentials are sorted out.

No production code for Task 10 should be written against a guessed shape while
this is open — Tasks 2-9 and 11 do not depend on the exact Wordstat wire format
and can proceed regardless.
