import 'package:flutter/material.dart';

/// Ecological-fallacy warning shown at the top of the UI on first open.
///
/// Required by the project's ethics review: the model relates deprivation change to
/// election outcomes at LOCAL AUTHORITY level only, so any association it surfaces is
/// between areas, not between people. Reading an individual's likely vote off an area-level
/// association is the ecological fallacy (the canonical illustration being the
/// chocolate-consumption vs Nobel-laureates correlation). Users must see these caveats
/// before drawing conclusions, so the banner is shown expanded by default and can be
/// collapsed but not permanently hidden.
class InterpretationBanner extends StatefulWidget {
  const InterpretationBanner({super.key});

  @override
  State<InterpretationBanner> createState() => _InterpretationBannerState();
}

class _InterpretationBannerState extends State<InterpretationBanner> {
  bool _expanded = true;

  static const _summary =
      'Area-level findings only — do not read individual voting behaviour from them.';

  static const _detail =
      'This tool compares deprivation indices with local election outcomes at local '
      'authority level. Where a change in deprivation is followed by a change in voting '
      'behaviour, that is an observation about AREAS, not about the people living in '
      'them: concluding that a particular person would vote a certain way because of '
      'where they live is the ecological fallacy.\n\n'
      'Voting behaviour is driven by far more than deprivation — immigration, national '
      'sentiment, local campaigns and candidates among them — and none of those are in '
      'this model. Treat anything here as a platform to augment existing analysis of '
      'voting behaviour, not as a definitive predictor of it.\n\n'
      'Clusters are deliberately named neutrally ("cluster-n", where n is the order the '
      'cluster was created) and carry no judgement about the areas in them.';

  @override
  Widget build(BuildContext context) {
    // 6.0:1 against the banner background — WCAG AA for body text.
    const amber = Color(0xFF8A5200);
    return Material(
      color: const Color(0xFFFFF8E1),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: amber, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'How to read these results: $_summary',
                    style: TextStyle(fontWeight: FontWeight.bold, color: amber),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Hide detail' : 'Read more'),
                ),
              ],
            ),
            if (_expanded)
              // The banner sits above every screen and takes its intrinsic height, so
              // on a short or narrow viewport the detail would push the app off-screen.
              // Cap it and let it scroll instead.
              // Flexible so it also shrinks when the incoming height IS bounded;
              // ConstrainedBox caps it when the parent gives unbounded height.
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: const SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(28, 4, 8, 4),
                    child: Text(_detail, style: TextStyle(height: 1.4)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
