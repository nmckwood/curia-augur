import 'package:flutter/material.dart';

import '../models/analysis.dart';
import 'metric_color.dart';

/// A collapsible, filterable table of the per-constituency data (REQ UI-7).
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
    final filtered = widget.constituencies
        .where((c) =>
            c.name.toLowerCase().contains(_filter.toLowerCase()) ||
            c.council.toLowerCase().contains(_filter.toLowerCase()))
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
            const Text('Local authority data',
                style: TextStyle(fontWeight: FontWeight.bold)),
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
            child: SingleChildScrollView(
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Local Authority')),
                  const DataColumn(label: Text('Council')),
                  const DataColumn(label: Text('Cluster')),
                  DataColumn(label: Text(widget.metric)),
                ],
                rows: filtered
                    .map(
                      (c) => DataRow(cells: [
                        DataCell(Text(c.name)),
                        DataCell(Text(c.council)),
                        DataCell(Text('${c.clusterId}')),
                        DataCell(Row(children: [
                          Container(
                            width: 12,
                            height: 12,
                            color: MetricColor.forValue(
                                _metricValue(c), minV, maxV),
                          ),
                          const SizedBox(width: 6),
                          Text('${_metricValue(c)}'),
                        ])),
                      ]),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }
}
