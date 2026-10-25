import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class ReelvaLicensePage extends StatefulWidget {
  const ReelvaLicensePage({
    super.key,
    required this.applicationName,
    required this.applicationVersion,
    required this.applicationIcon,
    required this.applicationLegalese,
  });

  final String applicationName;
  final String applicationVersion;
  final Widget applicationIcon;
  final String applicationLegalese;

  @override
  State<ReelvaLicensePage> createState() => _ReelvaLicensePageState();
}

class _ReelvaLicensePageState extends State<ReelvaLicensePage> {
  late final Future<Map<String, List<LicenseEntry>>> _licenses = _loadLicenses();
  String? _selectedPackage;

  Future<Map<String, List<LicenseEntry>>> _loadLicenses() async {
    final licenses = <String, List<LicenseEntry>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        (licenses[package] ??= <LicenseEntry>[]).add(entry);
      }
    }

    final firstPackage = licenses.isEmpty ? null : licenses.keys.first;
    final packages = licenses.keys.toList()
      ..sort((a, b) {
        if (a == b) return 0;
        if (a == firstPackage) return -1;
        if (b == firstPackage) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return {for (final package in packages) package: licenses[package]!};
  }

  Widget _buildApplicationInfo(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            widget.applicationName,
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall,
          ),
          widget.applicationIcon,
          Text(widget.applicationVersion, style: textTheme.bodyMedium),
          const SizedBox(height: 18),
          Text(
            widget.applicationLegalese,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          Text('Powered by Flutter', style: textTheme.bodyMedium),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 与 Flutter 原生许可证页保持相同的双栏断点。
        if (constraints.maxWidth < 840) {
          return LicensePage(
            applicationName: widget.applicationName,
            applicationVersion: widget.applicationVersion,
            applicationIcon: widget.applicationIcon,
            applicationLegalese: widget.applicationLegalese,
          );
        }

        final localizations = MaterialLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(title: Text(localizations.licensesPageTitle)),
          body: SafeArea(
            top: false,
            child: FutureBuilder<Map<String, List<LicenseEntry>>>(
              future: _licenses,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('开源许可证加载失败'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final licenses = snapshot.data!;
                final packages = licenses.keys.toList();
                final selectedPackage =
                    _selectedPackage ??
                    (packages.isEmpty ? null : packages.first);
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 320,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListView.builder(
                            primary: false,
                            padding: EdgeInsets.zero,
                            itemCount: packages.length + 1,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return _buildApplicationInfo(context);
                              }
                              final package = packages[index - 1];
                              return ListTile(
                                title: Text(package),
                                subtitle: Text(
                                  localizations.licensesPackageDetailText(
                                    licenses[package]!.length,
                                  ),
                                ),
                                selected: package == selectedPackage,
                                selectedTileColor: Theme.of(
                                  context,
                                ).highlightColor,
                                onTap: () => setState(() {
                                  _selectedPackage = package;
                                }),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: selectedPackage == null
                              ? const SizedBox.shrink()
                              : _LicenseDetails(
                                  key: ValueKey(selectedPackage),
                                  packageName: selectedPackage,
                                  licenses: licenses[selectedPackage]!,
                                ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _LicenseDetails extends StatefulWidget {
  const _LicenseDetails({
    super.key,
    required this.packageName,
    required this.licenses,
  });

  final String packageName;
  final List<LicenseEntry> licenses;

  @override
  State<_LicenseDetails> createState() => _LicenseDetailsState();
}

class _LicenseDetailsState extends State<_LicenseDetails> {
  late final Future<List<LicenseParagraph?>> _paragraphs = _loadParagraphs();

  Future<List<LicenseParagraph?>> _loadParagraphs() async {
    final paragraphs = <LicenseParagraph?>[];
    for (final license in widget.licenses) {
      if (!mounted) break;
      final entryParagraphs = await SchedulerBinding.instance.scheduleTask(
        () => license.paragraphs.toList(growable: false),
        Priority.animation,
      );
      if (paragraphs.isNotEmpty) paragraphs.add(null);
      paragraphs.addAll(entryParagraphs);
    }
    return paragraphs;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final localizations = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.packageName, style: textTheme.titleLarge),
              Text(
                localizations.licensesPackageDetailText(widget.licenses.length),
                style: textTheme.titleSmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<LicenseParagraph?>>(
            future: _paragraphs,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('许可证内容加载失败'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final paragraphs = snapshot.data!;
              return ListView.builder(
                primary: false,
                padding: const EdgeInsets.all(24),
                itemCount: paragraphs.length,
                itemBuilder: (context, index) {
                  final paragraph = paragraphs[index];
                  if (paragraph == null) return const Divider(height: 32);
                  final centered =
                      paragraph.indent == LicenseParagraph.centeredIndent;
                  return Padding(
                    padding: EdgeInsetsDirectional.only(
                      top: centered ? 16 : 8,
                      start: centered ? 0 : 16.0 * paragraph.indent,
                    ),
                    child: Text(
                      paragraph.text,
                      textAlign: centered ? TextAlign.center : TextAlign.start,
                      style: centered
                          ? textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            )
                          : textTheme.bodySmall,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
