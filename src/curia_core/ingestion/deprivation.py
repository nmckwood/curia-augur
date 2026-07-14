"""Aggregate LSOA-level deprivation data up to Local Authority District level and
compute year-over-year deltas.

Input files are LSOA-level (~33k rows). Per the user's decision we group by the
Local Authority District name column and mean-aggregate each of the 16 rank/decile
fields, then take delta = start_year - end_year (REQ Data-Ingestion-6).
"""

from curia_core.common.schemas import (
    DEPRIVATION_INPUT_FIELDS,
    DEPRIVATION_DELTA_KEYS,
)
from curia_core.ingestion.readers import detect_lad_column


def aggregate_to_lad(records):
    """Group LSOA records by LAD name and mean each deprivation field.

    Returns ``{lad_name: {field: mean_value}}``. Fields with no numeric values for a
    LAD are omitted.
    """
    if not records:
        return {}
    lad_col = detect_lad_column(records[0])
    if lad_col is None:
        raise ValueError("no Local Authority District name column found in deprivation data")

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
    """Compute integer deltas (start - end) per LAD present in BOTH years.

    Returns ``{lad_name: {"<field> delta": int, ...}}`` containing only LADs that have
    all 16 fields in both years (others are reported as unusable by the caller).
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
                entry[delta_key] = int(round(start_means[field] - end_means[field]))
            else:
                complete = False
                break
        if complete:
            deltas[lad] = entry
    return deltas
