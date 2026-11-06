-- One row per report: one Mac's counts for one day. No IP address, no identifier, no time of day.
CREATE TABLE reports (
    received   TEXT    NOT NULL,  -- UTC date the report arrived (YYYY-MM-DD)
    day        TEXT    NOT NULL,  -- the Mac's local date the counts are for
    app        TEXT    NOT NULL,  -- Speak version, e.g. "0.3"
    build      INTEGER NOT NULL,
    os         TEXT    NOT NULL,  -- macOS major.minor
    chip       TEXT    NOT NULL,  -- e.g. "Apple M1"
    locale     TEXT    NOT NULL,  -- e.g. "en-NZ"
    trigger    TEXT    NOT NULL,  -- fn, rightOption or rightCommand
    polish     INTEGER NOT NULL,  -- 1 if "Polish text" is on
    intelligence INTEGER NOT NULL, -- 1 if Apple Intelligence is available
    dictations INTEGER NOT NULL,
    words      INTEGER NOT NULL,  -- rounded to the nearest 10
    hold       INTEGER NOT NULL,
    hands_free INTEGER NOT NULL,
    empty      INTEGER NOT NULL,
    cancelled  INTEGER NOT NULL
);
CREATE INDEX reports_day ON reports (day);
