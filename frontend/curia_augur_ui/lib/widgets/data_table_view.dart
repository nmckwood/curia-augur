import 'package:flutter/material.dart';

import '../models/analysis.dart';
import '../theme/palette.dart';
import 'info_heading.dart';
import 'metric_color.dart';

/// A collapsible, filterable table of the per-constituency data (REQ UI-7), including
/// the cluster prediction and whether it matched the actual result (REQUIREMENTS_4 UI-4).
class DataTableView extends StatefulWidget {
  const DataTableView({
    super.key,
    required this.constituencies,
    required this.metric,
  });

  final List<Constituency> constituencies;
  final String metric;

  @override
  State<DataTableView> createState() => _DataTableViewState();
}

class _DataTableViewState extends State<DataTableView> {
  String _filter = '';
  bool _expanded = true;

  num _metricValue(Constituency c) => widget.metric == 'change_factor'
      ? c.changeFactor
      : (c.deciles[widget.metric] ?? 0);

  @override
  Widget build(BuildContext context) {
    final filtered =
        widget.constituencies
            .where(
              (c) =>
                  c.name.toLowerCase().contains(_filter.toLowerCase()) ||
                  c.council.toLowerCase().contains(_filter.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => _metricValue(b).compareTo(_metricValue(a)));

    final values = widget.constituencies.map(_metricValue).toList();
    final minV = values.isEmpty ? 0 : values.reduce((a, b) => a < b ? a : b);
    final maxV = values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
            const Flexible(
              child: InfoHeading(
                title: 'Local authority data',
                help:
                    'Every authority in the analysis, sorted by the deprivation '
                    'index chosen at the top of the page. "Actual" is what the '
                    'election did; "Cluster prediction" is what the clustering '
                    'said it would do; the tick or cross says whether they agreed. '
                    'This table is also the accessible equivalent of the maps and '
                    'charts — every value they encode as colour is written here as '
                    'text.',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Filter by name or council…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
          ],
        ),
        if (_expanded)
          Expanded(
            // Seven columns no longer fit a narrow window, so the table scrolls
            // horizontally rather than clipping columns off the right edge.
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('Local Authority')),
                    const DataColumn(label: Text('Council')),
                    const DataColumn(label: Text('Cluster')),
                    const DataColumn(label: Text('Actual')),
                    const DataColumn(label: Text('Cluster prediction')),
                    const DataColumn(label: Text('Correct')),
                    DataColumn(label: Text(widget.metric)),
                  ],
                  rows: filtered
                      .map(
                        (c) => DataRow(
                          cells: [
                            DataCell(Text(c.name)),
                            DataCell(Text(c.council)),
                            DataCell(Text('${c.clusterId}')),
                            DataCell(
                              Text(
                                c.changeFactor == 1 ? 'change' : 'no change',
                              ),
                            ),
                            DataCell(
                              Text(
                                c.changeFactorCluster == 1
                                    ? 'change'
                                    : 'no change',
                              ),
                            ),
                            // Icon + tooltip + the two text columns beside it, so
                            // correctness never depends on the colour (SC 1.4.1).
                            DataCell(
                              Tooltip(
                                message: c.clusterPredictionCorrect
                                    ? 'Cluster prediction matched the actual result'
                                    : 'Cluster prediction did not match the actual result',
                                child: Icon(
                                  c.clusterPredictionCorrect
                                      ? Icons.check
                                      : Icons.close,
                                  size: 16,
                                  semanticLabel: c.clusterPredictionCorrect
                                      ? 'correct'
                                      : 'incorrect',
                                  color: c.clusterPredictionCorrect
                                      ? Palette.correct
                                      : Palette.incorrect,
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    color: MetricColor.forValue(
                                      _metricValue(c),
                                      minV,
                                      maxV,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text('${_metricValue(c)}'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
