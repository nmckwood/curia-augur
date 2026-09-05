"""Compute per-council party seat deltas and the change_factor.

Election CSVs are one row per councillor, so a party's seat count for a council is the
number of councillor rows for that (council, party). We compute per-party deltas
(target - benchmark) and a change_factor which, per REQUIREMENTS_2, records whether the
party holding the majority (most councillors) CHANGED between the benchmark and target
year: 1 = the majority party flipped, 0 = it did not.
"""

COUNCIL_COLUMN = "Council"
PARTY_COLUMN = "Party Name"


def seat_counts(records):
    """Return ``{council: {party: seat_count}}`` from per-councillor rows."""
    counts = {}
    for row in records:
        council = (row.get(COUNCIL_COLUMN) or "").strip()
        party = (row.get(PARTY_COLUMN) or "").strip()
        if not council or not party:
            continue
        counts.setdefault(council, {})
        counts[council][party] = counts[council].get(party, 0) + 1
    return counts


def _majority_party(parties):
    """Party with the most councillors (ties broken by name for determinism); None if empty."""
    if not parties:
        return None
    return max(parties.items(), key=lambda kv: (kv[1], kv[0]))[0]


def _change_factor(benchmark_parties, target_parties):
    """1 if the majority party changed between benchmark and target, else 0.

    Both sides are guaranteed non-empty by the caller, which drops councils that are
    absent from either year rather than scoring them.
    """
    benchmark_majority = _majority_party(benchmark_parties)
    target_majority = _majority_party(target_parties)
    if benchmark_majority is None or target_majority is None:
        return 0
    return 1 if benchmark_majority != target_majority else 0


def build_election_results(benchmark_records, target_records):
    """Return ``(results, absent)``.

    ``results`` is ``{council: {"council":..., "change_factor":int, "<party>": delta_int}}``
    for every council present in BOTH years; per-party deltas are target - benchmark and
    change_factor is the binary majority-flip flag.

    ``absent`` lists councils that exist in the benchmark year but not the target year -
    almost always local-government reorganisation (e.g. the 2019-2023 Northamptonshire,
    Buckinghamshire, Cumbria and North Yorkshire mergers). They have no successor to
    compare against, so scoring them would silently label an abolished council as
    "did not change" and dilute the positive class. They are dropped and reported so the
    caller can log them.
    """
    benchmark = seat_counts(benchmark_records)
    target = seat_counts(target_records)

    results = {}
    absent = []
    for council, benchmark_parties in benchmark.items():
        target_parties = target.get(council)
        if not target_parties:
            absent.append(council)
            continue
        entry = {
            "council": council,
            "change_factor": _change_factor(benchmark_parties, target_parties),
        }
        for party in set(benchmark_parties) | set(target_parties):
            entry[party] = target_parties.get(party, 0) - benchmark_parties.get(party, 0)
        results[council] = entry
    return results, sorted(absent)
