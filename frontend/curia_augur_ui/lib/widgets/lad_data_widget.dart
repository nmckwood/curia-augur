import 'package:flutter/material.dart';

import '../models/analysis.dart';
import 'info_heading.dart';

/// Full-width local authority table (REQUIREMENTS_5 Widget 4): one row per
/// constituency with its deprivation delta map flattened into columns.
///
/// Columns come from the keys actually present in each record rather than from
/// meta.features_used, so the table stays correct whatever the analysis carries.
class LadDataWidget extends StatefulWidget {
  const LadDataWidget({super.key, required this.constituencies});

  final List<Constituency> constituencies;

  @override
  State<LadDataWidget> createState() => _LadDataWidgetState();
}

class _LadDataWidgetState extends State<LadDataWidget> {
  /// Height of the scrolling rows area when expanded.
  static const double _tableHeight = 380;

  String _filter = '';
  bool _expanded = true;

  // Nested scroll views need explicit controllers: a bare Scrollbar attaches to
  // the PrimaryScrollController and would otherwise latch onto the wrong axis.
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  /// Every decile key present across the data, in first-seen order.
  List<String> get _decileKeys => {
    for (final c in widget.constituencies) ...c.deciles.keys,
  }.toList();

  /// "Income Decile (where 1 is most deprived 10% of LSOAs) delta" -> "Income".
  String _shortLabel(String key) =>
      key.split(' Decile').first.split(' Rank').first;

  String _changeLabel(int v) => v == 1 ? 'change' : 'no change';

  /// Decile deltas are whole numbers; rank deltas are percentile-point floats
  /// that would otherwise render with a dozen meaningless decimal places.
  String _value(num? v) => switch (v) {
    null => '—',
    _ when v == v.roundToDouble() => '${v.toInt()}',
    _ => v.toStringAsFixed(2),
  };

  @override
  Widget build(BuildContext context) {
    final query = _filter.toLowerCase();
    final rows =
        widget.constituencies
            .where(
              (c) =>
                  c.name.toLowerCase().contains(query) ||
                  c.council.toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    final decileKeys = _decileKeys;
    final hasCommon = widget.constituencies.any((c) => c.predictedChange >= 0);
    final hasPerYear = widget.constituencies.any(
      (c) => c.predictedChangePerYear >= 0,
    );

    return Card(
      child: Column(
        // Owns its own height so it can sit directly in the page's scrolling
        // column without an outer box that has to be kept in sync with it.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  tooltip: _expanded ? 'Collapse table' : 'Expand table',
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
                Flexible(
                  child: InfoHeading(
                    title: 'Local authority data (${rows.length})',
                    help:
                        'One row per local authority, with every deprivation '
                        'index from its record shown as its own column. This '
                        'table is the accessible equivalent of the maps and '
                        'charts — every value they encode as colour is written '
                        'here as text. Scroll sideways for the remaining '
                        'indices.',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Filter by name or council…',
                      prefixIcon: Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
              ],
            ),
          ),
          if (_expanded)
            SizedBox(
              height: _tableHeight,
              // The horizontal bar is pinned to the bottom of the viewport (not
              // the content), so it stays put while the rows scroll underneath.
              child: Scrollbar(
                controller: _horizontal,
                thumbVisibility: true,
                trackVisibility: true,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _vertical,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DataTable(
                      headingRowHeight: 44,
                      dataRowMinHeight: 32,
                      dataRowMaxHeight: 32,
                      horizontalMargin: 12,
                      columnSpacing: 18,
                      columns: [
                        const DataColumn(label: Text('Local authority')),
                        const DataColumn(label: Text('Council')),
                        const DataColumn(label: Text('Cluster'), numeric: true),
                        const DataColumn(label: Text('Actual')),
                        const DataColumn(label: Text('Cluster prediction')),
                        const DataColumn(label: Text('Correct')),
                        if (hasCommon)
                          const DataColumn(
                            label: Text('Common-indices pred.'),
                          ),
                        if (hasPerYear)
                          const DataColumn(label: Text('Per-year pred.')),
                        const DataColumn(label: Text('PCA x'), numeric: true),
                        const DataColumn(label: Text('PCA y'), numeric: true),
                        for (final key in decileKeys)
                          DataColumn(
                            numeric: true,
                            label: Tooltip(
                              message: key,
                              child: Text(_shortLabel(key)),
                            ),
                          ),
                      ],
                      rows: [
                        for (final c in rows)
                          DataRow(
                            cells: [
                              DataCell(Text(c.name)),
                              DataCell(Text(c.council)),
                              DataCell(Text('${c.clusterId}')),
                              DataCell(Text(_changeLabel(c.changeFactor))),
                              DataCell(
                                Text(_changeLabel(c.changeFactorCluster)),
                              ),
                              DataCell(
                                Text(c.clusterPredictionCorrect ? 'yes' : 'no'),
                              ),
                              if (hasCommon)
                                DataCell(
                                  Text(
                                    c.predictedChange < 0
                                        ? '—'
                                        : _changeLabel(c.predictedChange),
                                  ),
                                ),
                              if (hasPerYear)
                                DataCell(
                                  Text(
                                    c.predictedChangePerYear < 0
                                        ? '—'
                                        : _changeLabel(
                                            c.predictedChangePerYear,
                                          ),
                                  ),
                                ),
                              DataCell(Text(c.pcaX.toStringAsFixed(3))),
                              DataCell(Text(c.pcaY.toStringAsFixed(3))),
                              for (final key in decileKeys)
                                DataCell(Text(_value(c.deciles[key]))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
