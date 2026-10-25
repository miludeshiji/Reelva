import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:reelva/shared/widgets/glass_widgets.dart';

import 'source_setup_page.dart';

class AddSourcePage extends StatelessWidget {
  const AddSourcePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: ReelvaDesign.background,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ReelvaDesign.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassPageHeader(
                    title: '添加媒体源',
                    leading: GlassIconButton(
                      key: const Key('add_source_back_button'),
                      icon: Icons.arrow_back,
                      size: ReelvaDesign.pageHeaderButtonSize,
                      tooltip: '返回媒体源',
                      onPressed: () => context.pop(),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        ReelvaDesign.space24,
                        ReelvaDesign.space8,
                        ReelvaDesign.space24,
                        ReelvaDesign.space32 +
                            MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '选择媒体来源',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: ReelvaDesign.space20),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final twoColumns =
                                  constraints.maxWidth >=
                                  ReelvaDesign.desktopBreakpoint -
                                      ReelvaDesign.space24 * 2;
                              final cardWidth = twoColumns
                                  ? (constraints.maxWidth -
                                            ReelvaDesign.space16) /
                                        2
                                  : constraints.maxWidth;

                              return Wrap(
                                spacing: ReelvaDesign.space16,
                                runSpacing: ReelvaDesign.space12,
                                children: [
                                  for (final kind in SourceSetupKind.values)
                                    SizedBox(
                                      width: cardWidth,
                                      child: GlassCard(
                                        key: Key(
                                          'add_source_type_${kind.name}',
                                        ),
                                        onTap: () => context.push(
                                          '/sources/add/${kind.name}',
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: theme
                                                    .colorScheme
                                                    .primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: Icon(
                                                kind.icon,
                                                color: ReelvaDesign.accent,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: ReelvaDesign.space16,
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    kind.label,
                                                    style: theme
                                                        .textTheme
                                                        .titleSmall,
                                                  ),
                                                  const SizedBox(
                                                    height: ReelvaDesign.space4,
                                                  ),
                                                  Text(
                                                    kind.description,
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: theme
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(
                                              width: ReelvaDesign.space8,
                                            ),
                                            Icon(
                                              Icons.chevron_right,
                                              size: 20,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
