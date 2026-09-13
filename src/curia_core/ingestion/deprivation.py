"""Aggregate LSOA-level deprivation data up to Local Authority District level and
compute year-over-year deltas.

Input files are LSOA-level (~33k rows). Per the user's decision we group by the
Local Authority District name column and mean-aggregate each of the 16 rank/decile
fields, then take delta = start_year - end_year (REQ Data-Ingestion-6). Ranks are
converted to within-edition national percentiles before differencing, because IoD
re-bases its ranks every release (see rank_scales).
"""

from curia_core.common.schemas import (
    DEPRIVATION_INPUT_FIELDS,
    DEPRIVATION_DELTA_KEYS,
    RANK_SUFFIX,
)
from curia_core.ingestion.readers import detect_lad_column


def _is_rank_field(field):
    return field.endswith(RANK_SUFFIX)


def rank_scales(records):
    """Return ``{rank_field: max_rank}`` - the number of ranked LSOAs in this edition.

    Ranks are re-based every IoD release, so they are NOT comparable across editions:
    IoD 2015 and 2019 both rank 32,844 LSOAs but IoD 2025 ranks 33,755 after the 2021
    census re-basing. Differencing raw ranks across editions therefore adds a systematic
    offset proportional to a LAD's rank (observed: IMD -300, Income -404, Education -544),
    which smuggles deprivation LEVEL into what is supposed to be a measure of CHANGE.
    Dividing by the edition's own max converts each rank to a national percentile, which
    is comparable across editions.
    """
    scales = {}
    for row in records:
        for field in DEPRIVATION_INPUT_FIELDS:
            if not _is_rank_field(field):
                continue
            value = row.get(field)
            if isinstance(value, (int, float)):
                scales[field] = max(scales.get(field, 0.0), float(value))
    return scales


def aggregate_to_lad(records):
    """Group LSOA records by LAD name and mean each deprivation field.

    Rank fields are converted to national percentile POINTS (0-100) within their own
    edition first, so that later cross-edition deltas are scale-free (see rank_scales).
    Decile fields are already 1-10 in every edition and are meaned as-is.

    Returns ``{lad_name: {field: mean_value}}``. Fields with no numeric values for a
    LAD are omitted.
    """
    if not records:
        return {}
    lad_col = detect_lad_column(records[0])
    if lad_col is None:
        raise ValueError("no Local Authority District name column found in deprivation data")

    scales = rank_scales(records)

    sums = {}
    counts = {}
    for row in records:
        lad = row.get(lad_col)
        if not lad:
            continue
        field_sums = sums.setdefault(lad, {})
        field_counts = counts.setdefault(lad, {})
        for field in DEPRIVATION_INPUT_FIELDS:
            value = row.get(field)
            if isinstance(value, (int, float)):
                if _is_rank_field(field):
                    scale = scales.get(field)
                    if not scale:
                        continue
                    value = float(value) / scale * 100.0
                field_sums[field] = field_sums.get(field, 0.0) + value
                field_counts[field] = field_counts.get(field, 0) + 1

    aggregated = {}
    for lad, field_sums in sums.items():
        means = {}
        for field, total in field_sums.items():
            n = counts[lad][field]
            if n:
                means[field] = total / n
        aggregated[lad] = means
    return aggregated


def compute_deltas(start_agg, end_agg):
    """Compute deltas (start - end) per LAD present in BOTH years.

    Rank deltas are a change in national percentile POINTS (float, -100..100); decile
    deltas remain whole deciles (int). Returns ``{lad_name: {"<field> delta": num, ...}}``
    containing only LADs that have all 16 fields in both years (others are reported as
    unusable by the caller).
    """
    deltas = {}
    for lad, start_means in start_agg.items():
        end_means = end_agg.get(lad)
        if end_means is None:
            continue
        entry = {}
        complete = True
        for field, delta_key in zip(DEPRIVATION_INPUT_FIELDS, DEPRIVATION_DELTA_KEYS):
            if field in start_means and field in end_means:
                difference = start_means[field] - end_means[field]
                # 4 dp on a 0-100 percentile scale is finer than the raw rank
                # granularity it replaces (1/32844 = 0.003 percentile points).
                entry[delta_key] = (
                    round(difference, 4) if _is_rank_field(field) else int(round(difference))
                )
            else:
                complete = False
                break
        if complete:
            deltas[lad] = entry
    return deltas
