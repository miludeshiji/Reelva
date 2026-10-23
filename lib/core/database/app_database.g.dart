// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MediaSourcesTable extends MediaSources
    with TableInfo<$MediaSourcesTable, MediaSourceEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rootLocatorMeta = const VerificationMeta(
    'rootLocator',
  );
  @override
  late final GeneratedColumn<String> rootLocator = GeneratedColumn<String>(
    'root_locator',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _credentialRefMeta = const VerificationMeta(
    'credentialRef',
  );
  @override
  late final GeneratedColumn<String> credentialRef = GeneratedColumn<String>(
    'credential_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _extensionsMeta = const VerificationMeta(
    'extensions',
  );
  @override
  late final GeneratedColumn<String> extensions = GeneratedColumn<String>(
    'extensions',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(
      r'["mkv","mp4","avi","mov","m4v","ts","webm"]',
    ),
  );
  static const VerificationMeta _excludedDirectoriesMeta =
      const VerificationMeta('excludedDirectories');
  @override
  late final GeneratedColumn<String> excludedDirectories =
      GeneratedColumn<String>(
        'excluded_directories',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(
          r'[".cache","$RECYCLE.BIN","System Volume Information"]',
        ),
      );
  static const VerificationMeta _scanRevisionMeta = const VerificationMeta(
    'scanRevision',
  );
  @override
  late final GeneratedColumn<int> scanRevision = GeneratedColumn<int>(
    'scan_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastScanAtMeta = const VerificationMeta(
    'lastScanAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastScanAt = GeneratedColumn<DateTime>(
    'last_scan_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    name,
    rootLocator,
    credentialRef,
    enabled,
    extensions,
    excludedDirectories,
    scanRevision,
    lastScanAt,
    errorMessage,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaSourceEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('root_locator')) {
      context.handle(
        _rootLocatorMeta,
        rootLocator.isAcceptableOrUnknown(
          data['root_locator']!,
          _rootLocatorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_rootLocatorMeta);
    }
    if (data.containsKey('credential_ref')) {
      context.handle(
        _credentialRefMeta,
        credentialRef.isAcceptableOrUnknown(
          data['credential_ref']!,
          _credentialRefMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('extensions')) {
      context.handle(
        _extensionsMeta,
        extensions.isAcceptableOrUnknown(data['extensions']!, _extensionsMeta),
      );
    }
    if (data.containsKey('excluded_directories')) {
      context.handle(
        _excludedDirectoriesMeta,
        excludedDirectories.isAcceptableOrUnknown(
          data['excluded_directories']!,
          _excludedDirectoriesMeta,
        ),
      );
    }
    if (data.containsKey('scan_revision')) {
      context.handle(
        _scanRevisionMeta,
        scanRevision.isAcceptableOrUnknown(
          data['scan_revision']!,
          _scanRevisionMeta,
        ),
      );
    }
    if (data.containsKey('last_scan_at')) {
      context.handle(
        _lastScanAtMeta,
        lastScanAt.isAcceptableOrUnknown(
          data['last_scan_at']!,
          _lastScanAtMeta,
        ),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {kind, rootLocator},
  ];
  @override
  MediaSourceEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaSourceEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      rootLocator: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}root_locator'],
      )!,
      credentialRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credential_ref'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      extensions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extensions'],
      )!,
      excludedDirectories: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}excluded_directories'],
      )!,
      scanRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scan_revision'],
      )!,
      lastScanAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_scan_at'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
    );
  }

  @override
  $MediaSourcesTable createAlias(String alias) {
    return $MediaSourcesTable(attachedDatabase, alias);
  }
}

class MediaSourceEntry extends DataClass
    implements Insertable<MediaSourceEntry> {
  final int id;
  final String kind;
  final String name;
  final String rootLocator;
  final String? credentialRef;
  final bool enabled;
  final String extensions;
  final String excludedDirectories;
  final int scanRevision;
  final DateTime? lastScanAt;
  final String? errorMessage;
  const MediaSourceEntry({
    required this.id,
    required this.kind,
    required this.name,
    required this.rootLocator,
    this.credentialRef,
    required this.enabled,
    required this.extensions,
    required this.excludedDirectories,
    required this.scanRevision,
    this.lastScanAt,
    this.errorMessage,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    map['root_locator'] = Variable<String>(rootLocator);
    if (!nullToAbsent || credentialRef != null) {
      map['credential_ref'] = Variable<String>(credentialRef);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['extensions'] = Variable<String>(extensions);
    map['excluded_directories'] = Variable<String>(excludedDirectories);
    map['scan_revision'] = Variable<int>(scanRevision);
    if (!nullToAbsent || lastScanAt != null) {
      map['last_scan_at'] = Variable<DateTime>(lastScanAt);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    return map;
  }

  MediaSourcesCompanion toCompanion(bool nullToAbsent) {
    return MediaSourcesCompanion(
      id: Value(id),
      kind: Value(kind),
      name: Value(name),
      rootLocator: Value(rootLocator),
      credentialRef: credentialRef == null && nullToAbsent
          ? const Value.absent()
          : Value(credentialRef),
      enabled: Value(enabled),
      extensions: Value(extensions),
      excludedDirectories: Value(excludedDirectories),
      scanRevision: Value(scanRevision),
      lastScanAt: lastScanAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastScanAt),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
    );
  }

  factory MediaSourceEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaSourceEntry(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      rootLocator: serializer.fromJson<String>(json['rootLocator']),
      credentialRef: serializer.fromJson<String?>(json['credentialRef']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      extensions: serializer.fromJson<String>(json['extensions']),
      excludedDirectories: serializer.fromJson<String>(
        json['excludedDirectories'],
      ),
      scanRevision: serializer.fromJson<int>(json['scanRevision']),
      lastScanAt: serializer.fromJson<DateTime?>(json['lastScanAt']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'rootLocator': serializer.toJson<String>(rootLocator),
      'credentialRef': serializer.toJson<String?>(credentialRef),
      'enabled': serializer.toJson<bool>(enabled),
      'extensions': serializer.toJson<String>(extensions),
      'excludedDirectories': serializer.toJson<String>(excludedDirectories),
      'scanRevision': serializer.toJson<int>(scanRevision),
      'lastScanAt': serializer.toJson<DateTime?>(lastScanAt),
      'errorMessage': serializer.toJson<String?>(errorMessage),
    };
  }

  MediaSourceEntry copyWith({
    int? id,
    String? kind,
    String? name,
    String? rootLocator,
    Value<String?> credentialRef = const Value.absent(),
    bool? enabled,
    String? extensions,
    String? excludedDirectories,
    int? scanRevision,
    Value<DateTime?> lastScanAt = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
  }) => MediaSourceEntry(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    rootLocator: rootLocator ?? this.rootLocator,
    credentialRef: credentialRef.present
        ? credentialRef.value
        : this.credentialRef,
    enabled: enabled ?? this.enabled,
    extensions: extensions ?? this.extensions,
    excludedDirectories: excludedDirectories ?? this.excludedDirectories,
    scanRevision: scanRevision ?? this.scanRevision,
    lastScanAt: lastScanAt.present ? lastScanAt.value : this.lastScanAt,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
  );
  MediaSourceEntry copyWithCompanion(MediaSourcesCompanion data) {
    return MediaSourceEntry(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      rootLocator: data.rootLocator.present
          ? data.rootLocator.value
          : this.rootLocator,
      credentialRef: data.credentialRef.present
          ? data.credentialRef.value
          : this.credentialRef,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      extensions: data.extensions.present
          ? data.extensions.value
          : this.extensions,
      excludedDirectories: data.excludedDirectories.present
          ? data.excludedDirectories.value
          : this.excludedDirectories,
      scanRevision: data.scanRevision.present
          ? data.scanRevision.value
          : this.scanRevision,
      lastScanAt: data.lastScanAt.present
          ? data.lastScanAt.value
          : this.lastScanAt,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaSourceEntry(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('rootLocator: $rootLocator, ')
          ..write('credentialRef: $credentialRef, ')
          ..write('enabled: $enabled, ')
          ..write('extensions: $extensions, ')
          ..write('excludedDirectories: $excludedDirectories, ')
          ..write('scanRevision: $scanRevision, ')
          ..write('lastScanAt: $lastScanAt, ')
          ..write('errorMessage: $errorMessage')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    name,
    rootLocator,
    credentialRef,
    enabled,
    extensions,
    excludedDirectories,
    scanRevision,
    lastScanAt,
    errorMessage,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaSourceEntry &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.rootLocator == this.rootLocator &&
          other.credentialRef == this.credentialRef &&
          other.enabled == this.enabled &&
          other.extensions == this.extensions &&
          other.excludedDirectories == this.excludedDirectories &&
          other.scanRevision == this.scanRevision &&
          other.lastScanAt == this.lastScanAt &&
          other.errorMessage == this.errorMessage);
}

class MediaSourcesCompanion extends UpdateCompanion<MediaSourceEntry> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String> name;
  final Value<String> rootLocator;
  final Value<String?> credentialRef;
  final Value<bool> enabled;
  final Value<String> extensions;
  final Value<String> excludedDirectories;
  final Value<int> scanRevision;
  final Value<DateTime?> lastScanAt;
  final Value<String?> errorMessage;
  const MediaSourcesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.rootLocator = const Value.absent(),
    this.credentialRef = const Value.absent(),
    this.enabled = const Value.absent(),
    this.extensions = const Value.absent(),
    this.excludedDirectories = const Value.absent(),
    this.scanRevision = const Value.absent(),
    this.lastScanAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
  });
  MediaSourcesCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required String name,
    required String rootLocator,
    this.credentialRef = const Value.absent(),
    this.enabled = const Value.absent(),
    this.extensions = const Value.absent(),
    this.excludedDirectories = const Value.absent(),
    this.scanRevision = const Value.absent(),
    this.lastScanAt = const Value.absent(),
    this.errorMessage = const Value.absent(),
  }) : kind = Value(kind),
       name = Value(name),
       rootLocator = Value(rootLocator);
  static Insertable<MediaSourceEntry> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<String>? rootLocator,
    Expression<String>? credentialRef,
    Expression<bool>? enabled,
    Expression<String>? extensions,
    Expression<String>? excludedDirectories,
    Expression<int>? scanRevision,
    Expression<DateTime>? lastScanAt,
    Expression<String>? errorMessage,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (rootLocator != null) 'root_locator': rootLocator,
      if (credentialRef != null) 'credential_ref': credentialRef,
      if (enabled != null) 'enabled': enabled,
      if (extensions != null) 'extensions': extensions,
      if (excludedDirectories != null)
        'excluded_directories': excludedDirectories,
      if (scanRevision != null) 'scan_revision': scanRevision,
      if (lastScanAt != null) 'last_scan_at': lastScanAt,
      if (errorMessage != null) 'error_message': errorMessage,
    });
  }

  MediaSourcesCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String>? name,
    Value<String>? rootLocator,
    Value<String?>? credentialRef,
    Value<bool>? enabled,
    Value<String>? extensions,
    Value<String>? excludedDirectories,
    Value<int>? scanRevision,
    Value<DateTime?>? lastScanAt,
    Value<String?>? errorMessage,
  }) {
    return MediaSourcesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      rootLocator: rootLocator ?? this.rootLocator,
      credentialRef: credentialRef ?? this.credentialRef,
      enabled: enabled ?? this.enabled,
      extensions: extensions ?? this.extensions,
      excludedDirectories: excludedDirectories ?? this.excludedDirectories,
      scanRevision: scanRevision ?? this.scanRevision,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rootLocator.present) {
      map['root_locator'] = Variable<String>(rootLocator.value);
    }
    if (credentialRef.present) {
      map['credential_ref'] = Variable<String>(credentialRef.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (extensions.present) {
      map['extensions'] = Variable<String>(extensions.value);
    }
    if (excludedDirectories.present) {
      map['excluded_directories'] = Variable<String>(excludedDirectories.value);
    }
    if (scanRevision.present) {
      map['scan_revision'] = Variable<int>(scanRevision.value);
    }
    if (lastScanAt.present) {
      map['last_scan_at'] = Variable<DateTime>(lastScanAt.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaSourcesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('rootLocator: $rootLocator, ')
          ..write('credentialRef: $credentialRef, ')
          ..write('enabled: $enabled, ')
          ..write('extensions: $extensions, ')
          ..write('excludedDirectories: $excludedDirectories, ')
          ..write('scanRevision: $scanRevision, ')
          ..write('lastScanAt: $lastScanAt, ')
          ..write('errorMessage: $errorMessage')
          ..write(')'))
        .toString();
  }
}

class $MediaEntriesTable extends MediaEntries
    with TableInfo<$MediaEntriesTable, MediaEntryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES media_sources (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _externalEntryIdMeta = const VerificationMeta(
    'externalEntryId',
  );
  @override
  late final GeneratedColumn<String> externalEntryId = GeneratedColumn<String>(
    'external_entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativeLocatorMeta = const VerificationMeta(
    'relativeLocator',
  );
  @override
  late final GeneratedColumn<String> relativeLocator = GeneratedColumn<String>(
    'relative_locator',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDirectoryMeta = const VerificationMeta(
    'isDirectory',
  );
  @override
  late final GeneratedColumn<bool> isDirectory = GeneratedColumn<bool>(
    'is_directory',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_directory" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<int> modifiedAt = GeneratedColumn<int>(
    'modified_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _availableMeta = const VerificationMeta(
    'available',
  );
  @override
  late final GeneratedColumn<bool> available = GeneratedColumn<bool>(
    'available',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("available" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _lastSeenScanIdMeta = const VerificationMeta(
    'lastSeenScanId',
  );
  @override
  late final GeneratedColumn<int> lastSeenScanId = GeneratedColumn<int>(
    'last_seen_scan_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceId,
    externalEntryId,
    relativeLocator,
    name,
    isDirectory,
    size,
    modifiedAt,
    etag,
    available,
    lastSeenScanId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaEntryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('external_entry_id')) {
      context.handle(
        _externalEntryIdMeta,
        externalEntryId.isAcceptableOrUnknown(
          data['external_entry_id']!,
          _externalEntryIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_externalEntryIdMeta);
    }
    if (data.containsKey('relative_locator')) {
      context.handle(
        _relativeLocatorMeta,
        relativeLocator.isAcceptableOrUnknown(
          data['relative_locator']!,
          _relativeLocatorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativeLocatorMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_directory')) {
      context.handle(
        _isDirectoryMeta,
        isDirectory.isAcceptableOrUnknown(
          data['is_directory']!,
          _isDirectoryMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_isDirectoryMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('available')) {
      context.handle(
        _availableMeta,
        available.isAcceptableOrUnknown(data['available']!, _availableMeta),
      );
    }
    if (data.containsKey('last_seen_scan_id')) {
      context.handle(
        _lastSeenScanIdMeta,
        lastSeenScanId.isAcceptableOrUnknown(
          data['last_seen_scan_id']!,
          _lastSeenScanIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sourceId, externalEntryId},
  ];
  @override
  MediaEntryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaEntryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      externalEntryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_entry_id'],
      )!,
      relativeLocator: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_locator'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      isDirectory: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_directory'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      ),
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified_at'],
      ),
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      available: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}available'],
      )!,
      lastSeenScanId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_scan_id'],
      )!,
    );
  }

  @override
  $MediaEntriesTable createAlias(String alias) {
    return $MediaEntriesTable(attachedDatabase, alias);
  }
}

class MediaEntryData extends DataClass implements Insertable<MediaEntryData> {
  final int id;
  final int sourceId;
  final String externalEntryId;
  final String relativeLocator;
  final String name;
  final bool isDirectory;
  final int? size;
  final int? modifiedAt;
  final String? etag;
  final bool available;
  final int lastSeenScanId;
  const MediaEntryData({
    required this.id,
    required this.sourceId,
    required this.externalEntryId,
    required this.relativeLocator,
    required this.name,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
    this.etag,
    required this.available,
    required this.lastSeenScanId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_id'] = Variable<int>(sourceId);
    map['external_entry_id'] = Variable<String>(externalEntryId);
    map['relative_locator'] = Variable<String>(relativeLocator);
    map['name'] = Variable<String>(name);
    map['is_directory'] = Variable<bool>(isDirectory);
    if (!nullToAbsent || size != null) {
      map['size'] = Variable<int>(size);
    }
    if (!nullToAbsent || modifiedAt != null) {
      map['modified_at'] = Variable<int>(modifiedAt);
    }
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    map['available'] = Variable<bool>(available);
    map['last_seen_scan_id'] = Variable<int>(lastSeenScanId);
    return map;
  }

  MediaEntriesCompanion toCompanion(bool nullToAbsent) {
    return MediaEntriesCompanion(
      id: Value(id),
      sourceId: Value(sourceId),
      externalEntryId: Value(externalEntryId),
      relativeLocator: Value(relativeLocator),
      name: Value(name),
      isDirectory: Value(isDirectory),
      size: size == null && nullToAbsent ? const Value.absent() : Value(size),
      modifiedAt: modifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(modifiedAt),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      available: Value(available),
      lastSeenScanId: Value(lastSeenScanId),
    );
  }

  factory MediaEntryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaEntryData(
      id: serializer.fromJson<int>(json['id']),
      sourceId: serializer.fromJson<int>(json['sourceId']),
      externalEntryId: serializer.fromJson<String>(json['externalEntryId']),
      relativeLocator: serializer.fromJson<String>(json['relativeLocator']),
      name: serializer.fromJson<String>(json['name']),
      isDirectory: serializer.fromJson<bool>(json['isDirectory']),
      size: serializer.fromJson<int?>(json['size']),
      modifiedAt: serializer.fromJson<int?>(json['modifiedAt']),
      etag: serializer.fromJson<String?>(json['etag']),
      available: serializer.fromJson<bool>(json['available']),
      lastSeenScanId: serializer.fromJson<int>(json['lastSeenScanId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceId': serializer.toJson<int>(sourceId),
      'externalEntryId': serializer.toJson<String>(externalEntryId),
      'relativeLocator': serializer.toJson<String>(relativeLocator),
      'name': serializer.toJson<String>(name),
      'isDirectory': serializer.toJson<bool>(isDirectory),
      'size': serializer.toJson<int?>(size),
      'modifiedAt': serializer.toJson<int?>(modifiedAt),
      'etag': serializer.toJson<String?>(etag),
      'available': serializer.toJson<bool>(available),
      'lastSeenScanId': serializer.toJson<int>(lastSeenScanId),
    };
  }

  MediaEntryData copyWith({
    int? id,
    int? sourceId,
    String? externalEntryId,
    String? relativeLocator,
    String? name,
    bool? isDirectory,
    Value<int?> size = const Value.absent(),
    Value<int?> modifiedAt = const Value.absent(),
    Value<String?> etag = const Value.absent(),
    bool? available,
    int? lastSeenScanId,
  }) => MediaEntryData(
    id: id ?? this.id,
    sourceId: sourceId ?? this.sourceId,
    externalEntryId: externalEntryId ?? this.externalEntryId,
    relativeLocator: relativeLocator ?? this.relativeLocator,
    name: name ?? this.name,
    isDirectory: isDirectory ?? this.isDirectory,
    size: size.present ? size.value : this.size,
    modifiedAt: modifiedAt.present ? modifiedAt.value : this.modifiedAt,
    etag: etag.present ? etag.value : this.etag,
    available: available ?? this.available,
    lastSeenScanId: lastSeenScanId ?? this.lastSeenScanId,
  );
  MediaEntryData copyWithCompanion(MediaEntriesCompanion data) {
    return MediaEntryData(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      externalEntryId: data.externalEntryId.present
          ? data.externalEntryId.value
          : this.externalEntryId,
      relativeLocator: data.relativeLocator.present
          ? data.relativeLocator.value
          : this.relativeLocator,
      name: data.name.present ? data.name.value : this.name,
      isDirectory: data.isDirectory.present
          ? data.isDirectory.value
          : this.isDirectory,
      size: data.size.present ? data.size.value : this.size,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      etag: data.etag.present ? data.etag.value : this.etag,
      available: data.available.present ? data.available.value : this.available,
      lastSeenScanId: data.lastSeenScanId.present
          ? data.lastSeenScanId.value
          : this.lastSeenScanId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaEntryData(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('externalEntryId: $externalEntryId, ')
          ..write('relativeLocator: $relativeLocator, ')
          ..write('name: $name, ')
          ..write('isDirectory: $isDirectory, ')
          ..write('size: $size, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('etag: $etag, ')
          ..write('available: $available, ')
          ..write('lastSeenScanId: $lastSeenScanId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceId,
    externalEntryId,
    relativeLocator,
    name,
    isDirectory,
    size,
    modifiedAt,
    etag,
    available,
    lastSeenScanId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaEntryData &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.externalEntryId == this.externalEntryId &&
          other.relativeLocator == this.relativeLocator &&
          other.name == this.name &&
          other.isDirectory == this.isDirectory &&
          other.size == this.size &&
          other.modifiedAt == this.modifiedAt &&
          other.etag == this.etag &&
          other.available == this.available &&
          other.lastSeenScanId == this.lastSeenScanId);
}

class MediaEntriesCompanion extends UpdateCompanion<MediaEntryData> {
  final Value<int> id;
  final Value<int> sourceId;
  final Value<String> externalEntryId;
  final Value<String> relativeLocator;
  final Value<String> name;
  final Value<bool> isDirectory;
  final Value<int?> size;
  final Value<int?> modifiedAt;
  final Value<String?> etag;
  final Value<bool> available;
  final Value<int> lastSeenScanId;
  const MediaEntriesCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.externalEntryId = const Value.absent(),
    this.relativeLocator = const Value.absent(),
    this.name = const Value.absent(),
    this.isDirectory = const Value.absent(),
    this.size = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.etag = const Value.absent(),
    this.available = const Value.absent(),
    this.lastSeenScanId = const Value.absent(),
  });
  MediaEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int sourceId,
    required String externalEntryId,
    required String relativeLocator,
    required String name,
    required bool isDirectory,
    this.size = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.etag = const Value.absent(),
    this.available = const Value.absent(),
    this.lastSeenScanId = const Value.absent(),
  }) : sourceId = Value(sourceId),
       externalEntryId = Value(externalEntryId),
       relativeLocator = Value(relativeLocator),
       name = Value(name),
       isDirectory = Value(isDirectory);
  static Insertable<MediaEntryData> custom({
    Expression<int>? id,
    Expression<int>? sourceId,
    Expression<String>? externalEntryId,
    Expression<String>? relativeLocator,
    Expression<String>? name,
    Expression<bool>? isDirectory,
    Expression<int>? size,
    Expression<int>? modifiedAt,
    Expression<String>? etag,
    Expression<bool>? available,
    Expression<int>? lastSeenScanId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (externalEntryId != null) 'external_entry_id': externalEntryId,
      if (relativeLocator != null) 'relative_locator': relativeLocator,
      if (name != null) 'name': name,
      if (isDirectory != null) 'is_directory': isDirectory,
      if (size != null) 'size': size,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (etag != null) 'etag': etag,
      if (available != null) 'available': available,
      if (lastSeenScanId != null) 'last_seen_scan_id': lastSeenScanId,
    });
  }

  MediaEntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? sourceId,
    Value<String>? externalEntryId,
    Value<String>? relativeLocator,
    Value<String>? name,
    Value<bool>? isDirectory,
    Value<int?>? size,
    Value<int?>? modifiedAt,
    Value<String?>? etag,
    Value<bool>? available,
    Value<int>? lastSeenScanId,
  }) {
    return MediaEntriesCompanion(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      externalEntryId: externalEntryId ?? this.externalEntryId,
      relativeLocator: relativeLocator ?? this.relativeLocator,
      name: name ?? this.name,
      isDirectory: isDirectory ?? this.isDirectory,
      size: size ?? this.size,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      etag: etag ?? this.etag,
      available: available ?? this.available,
      lastSeenScanId: lastSeenScanId ?? this.lastSeenScanId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (externalEntryId.present) {
      map['external_entry_id'] = Variable<String>(externalEntryId.value);
    }
    if (relativeLocator.present) {
      map['relative_locator'] = Variable<String>(relativeLocator.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isDirectory.present) {
      map['is_directory'] = Variable<bool>(isDirectory.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<int>(modifiedAt.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (available.present) {
      map['available'] = Variable<bool>(available.value);
    }
    if (lastSeenScanId.present) {
      map['last_seen_scan_id'] = Variable<int>(lastSeenScanId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaEntriesCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('externalEntryId: $externalEntryId, ')
          ..write('relativeLocator: $relativeLocator, ')
          ..write('name: $name, ')
          ..write('isDirectory: $isDirectory, ')
          ..write('size: $size, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('etag: $etag, ')
          ..write('available: $available, ')
          ..write('lastSeenScanId: $lastSeenScanId')
          ..write(')'))
        .toString();
  }
}

class $MediaFilesTable extends MediaFiles
    with TableInfo<$MediaFilesTable, MediaFileData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<int> entryId = GeneratedColumn<int>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES media_entries (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _containerMeta = const VerificationMeta(
    'container',
  );
  @override
  late final GeneratedColumn<String> container = GeneratedColumn<String>(
    'container',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolutionWidthMeta = const VerificationMeta(
    'resolutionWidth',
  );
  @override
  late final GeneratedColumn<int> resolutionWidth = GeneratedColumn<int>(
    'resolution_width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolutionHeightMeta = const VerificationMeta(
    'resolutionHeight',
  );
  @override
  late final GeneratedColumn<int> resolutionHeight = GeneratedColumn<int>(
    'resolution_height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _videoCodecMeta = const VerificationMeta(
    'videoCodec',
  );
  @override
  late final GeneratedColumn<String> videoCodec = GeneratedColumn<String>(
    'video_codec',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioCodecMeta = const VerificationMeta(
    'audioCodec',
  );
  @override
  late final GeneratedColumn<String> audioCodec = GeneratedColumn<String>(
    'audio_codec',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parseStateMeta = const VerificationMeta(
    'parseState',
  );
  @override
  late final GeneratedColumn<String> parseState = GeneratedColumn<String>(
    'parse_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _candidateTypeMeta = const VerificationMeta(
    'candidateType',
  );
  @override
  late final GeneratedColumn<String> candidateType = GeneratedColumn<String>(
    'candidate_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _candidateSeasonNumberMeta =
      const VerificationMeta('candidateSeasonNumber');
  @override
  late final GeneratedColumn<int> candidateSeasonNumber = GeneratedColumn<int>(
    'candidate_season_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _candidateEpisodeNumberMeta =
      const VerificationMeta('candidateEpisodeNumber');
  @override
  late final GeneratedColumn<int> candidateEpisodeNumber = GeneratedColumn<int>(
    'candidate_episode_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _candidateDetailsMeta = const VerificationMeta(
    'candidateDetails',
  );
  @override
  late final GeneratedColumn<String> candidateDetails = GeneratedColumn<String>(
    'candidate_details',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entryId,
    container,
    durationMs,
    resolutionWidth,
    resolutionHeight,
    videoCodec,
    audioCodec,
    parseState,
    candidateType,
    candidateSeasonNumber,
    candidateEpisodeNumber,
    candidateDetails,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaFileData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('container')) {
      context.handle(
        _containerMeta,
        container.isAcceptableOrUnknown(data['container']!, _containerMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('resolution_width')) {
      context.handle(
        _resolutionWidthMeta,
        resolutionWidth.isAcceptableOrUnknown(
          data['resolution_width']!,
          _resolutionWidthMeta,
        ),
      );
    }
    if (data.containsKey('resolution_height')) {
      context.handle(
        _resolutionHeightMeta,
        resolutionHeight.isAcceptableOrUnknown(
          data['resolution_height']!,
          _resolutionHeightMeta,
        ),
      );
    }
    if (data.containsKey('video_codec')) {
      context.handle(
        _videoCodecMeta,
        videoCodec.isAcceptableOrUnknown(data['video_codec']!, _videoCodecMeta),
      );
    }
    if (data.containsKey('audio_codec')) {
      context.handle(
        _audioCodecMeta,
        audioCodec.isAcceptableOrUnknown(data['audio_codec']!, _audioCodecMeta),
      );
    }
    if (data.containsKey('parse_state')) {
      context.handle(
        _parseStateMeta,
        parseState.isAcceptableOrUnknown(data['parse_state']!, _parseStateMeta),
      );
    }
    if (data.containsKey('candidate_type')) {
      context.handle(
        _candidateTypeMeta,
        candidateType.isAcceptableOrUnknown(
          data['candidate_type']!,
          _candidateTypeMeta,
        ),
      );
    }
    if (data.containsKey('candidate_season_number')) {
      context.handle(
        _candidateSeasonNumberMeta,
        candidateSeasonNumber.isAcceptableOrUnknown(
          data['candidate_season_number']!,
          _candidateSeasonNumberMeta,
        ),
      );
    }
    if (data.containsKey('candidate_episode_number')) {
      context.handle(
        _candidateEpisodeNumberMeta,
        candidateEpisodeNumber.isAcceptableOrUnknown(
          data['candidate_episode_number']!,
          _candidateEpisodeNumberMeta,
        ),
      );
    }
    if (data.containsKey('candidate_details')) {
      context.handle(
        _candidateDetailsMeta,
        candidateDetails.isAcceptableOrUnknown(
          data['candidate_details']!,
          _candidateDetailsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaFileData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaFileData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entry_id'],
      )!,
      container: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}container'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      resolutionWidth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolution_width'],
      ),
      resolutionHeight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolution_height'],
      ),
      videoCodec: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_codec'],
      ),
      audioCodec: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_codec'],
      ),
      parseState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parse_state'],
      )!,
      candidateType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}candidate_type'],
      ),
      candidateSeasonNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}candidate_season_number'],
      ),
      candidateEpisodeNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}candidate_episode_number'],
      ),
      candidateDetails: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}candidate_details'],
      ),
    );
  }

  @override
  $MediaFilesTable createAlias(String alias) {
    return $MediaFilesTable(attachedDatabase, alias);
  }
}

class MediaFileData extends DataClass implements Insertable<MediaFileData> {
  final int id;
  final int entryId;
  final String? container;
  final int? durationMs;
  final int? resolutionWidth;
  final int? resolutionHeight;
  final String? videoCodec;
  final String? audioCodec;
  final String parseState;
  final String? candidateType;
  final int? candidateSeasonNumber;
  final int? candidateEpisodeNumber;
  final String? candidateDetails;
  const MediaFileData({
    required this.id,
    required this.entryId,
    this.container,
    this.durationMs,
    this.resolutionWidth,
    this.resolutionHeight,
    this.videoCodec,
    this.audioCodec,
    required this.parseState,
    this.candidateType,
    this.candidateSeasonNumber,
    this.candidateEpisodeNumber,
    this.candidateDetails,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entry_id'] = Variable<int>(entryId);
    if (!nullToAbsent || container != null) {
      map['container'] = Variable<String>(container);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || resolutionWidth != null) {
      map['resolution_width'] = Variable<int>(resolutionWidth);
    }
    if (!nullToAbsent || resolutionHeight != null) {
      map['resolution_height'] = Variable<int>(resolutionHeight);
    }
    if (!nullToAbsent || videoCodec != null) {
      map['video_codec'] = Variable<String>(videoCodec);
    }
    if (!nullToAbsent || audioCodec != null) {
      map['audio_codec'] = Variable<String>(audioCodec);
    }
    map['parse_state'] = Variable<String>(parseState);
    if (!nullToAbsent || candidateType != null) {
      map['candidate_type'] = Variable<String>(candidateType);
    }
    if (!nullToAbsent || candidateSeasonNumber != null) {
      map['candidate_season_number'] = Variable<int>(candidateSeasonNumber);
    }
    if (!nullToAbsent || candidateEpisodeNumber != null) {
      map['candidate_episode_number'] = Variable<int>(candidateEpisodeNumber);
    }
    if (!nullToAbsent || candidateDetails != null) {
      map['candidate_details'] = Variable<String>(candidateDetails);
    }
    return map;
  }

  MediaFilesCompanion toCompanion(bool nullToAbsent) {
    return MediaFilesCompanion(
      id: Value(id),
      entryId: Value(entryId),
      container: container == null && nullToAbsent
          ? const Value.absent()
          : Value(container),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      resolutionWidth: resolutionWidth == null && nullToAbsent
          ? const Value.absent()
          : Value(resolutionWidth),
      resolutionHeight: resolutionHeight == null && nullToAbsent
          ? const Value.absent()
          : Value(resolutionHeight),
      videoCodec: videoCodec == null && nullToAbsent
          ? const Value.absent()
          : Value(videoCodec),
      audioCodec: audioCodec == null && nullToAbsent
          ? const Value.absent()
          : Value(audioCodec),
      parseState: Value(parseState),
      candidateType: candidateType == null && nullToAbsent
          ? const Value.absent()
          : Value(candidateType),
      candidateSeasonNumber: candidateSeasonNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(candidateSeasonNumber),
      candidateEpisodeNumber: candidateEpisodeNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(candidateEpisodeNumber),
      candidateDetails: candidateDetails == null && nullToAbsent
          ? const Value.absent()
          : Value(candidateDetails),
    );
  }

  factory MediaFileData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaFileData(
      id: serializer.fromJson<int>(json['id']),
      entryId: serializer.fromJson<int>(json['entryId']),
      container: serializer.fromJson<String?>(json['container']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      resolutionWidth: serializer.fromJson<int?>(json['resolutionWidth']),
      resolutionHeight: serializer.fromJson<int?>(json['resolutionHeight']),
      videoCodec: serializer.fromJson<String?>(json['videoCodec']),
      audioCodec: serializer.fromJson<String?>(json['audioCodec']),
      parseState: serializer.fromJson<String>(json['parseState']),
      candidateType: serializer.fromJson<String?>(json['candidateType']),
      candidateSeasonNumber: serializer.fromJson<int?>(
        json['candidateSeasonNumber'],
      ),
      candidateEpisodeNumber: serializer.fromJson<int?>(
        json['candidateEpisodeNumber'],
      ),
      candidateDetails: serializer.fromJson<String?>(json['candidateDetails']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entryId': serializer.toJson<int>(entryId),
      'container': serializer.toJson<String?>(container),
      'durationMs': serializer.toJson<int?>(durationMs),
      'resolutionWidth': serializer.toJson<int?>(resolutionWidth),
      'resolutionHeight': serializer.toJson<int?>(resolutionHeight),
      'videoCodec': serializer.toJson<String?>(videoCodec),
      'audioCodec': serializer.toJson<String?>(audioCodec),
      'parseState': serializer.toJson<String>(parseState),
      'candidateType': serializer.toJson<String?>(candidateType),
      'candidateSeasonNumber': serializer.toJson<int?>(candidateSeasonNumber),
      'candidateEpisodeNumber': serializer.toJson<int?>(candidateEpisodeNumber),
      'candidateDetails': serializer.toJson<String?>(candidateDetails),
    };
  }

  MediaFileData copyWith({
    int? id,
    int? entryId,
    Value<String?> container = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<int?> resolutionWidth = const Value.absent(),
    Value<int?> resolutionHeight = const Value.absent(),
    Value<String?> videoCodec = const Value.absent(),
    Value<String?> audioCodec = const Value.absent(),
    String? parseState,
    Value<String?> candidateType = const Value.absent(),
    Value<int?> candidateSeasonNumber = const Value.absent(),
    Value<int?> candidateEpisodeNumber = const Value.absent(),
    Value<String?> candidateDetails = const Value.absent(),
  }) => MediaFileData(
    id: id ?? this.id,
    entryId: entryId ?? this.entryId,
    container: container.present ? container.value : this.container,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    resolutionWidth: resolutionWidth.present
        ? resolutionWidth.value
        : this.resolutionWidth,
    resolutionHeight: resolutionHeight.present
        ? resolutionHeight.value
        : this.resolutionHeight,
    videoCodec: videoCodec.present ? videoCodec.value : this.videoCodec,
    audioCodec: audioCodec.present ? audioCodec.value : this.audioCodec,
    parseState: parseState ?? this.parseState,
    candidateType: candidateType.present
        ? candidateType.value
        : this.candidateType,
    candidateSeasonNumber: candidateSeasonNumber.present
        ? candidateSeasonNumber.value
        : this.candidateSeasonNumber,
    candidateEpisodeNumber: candidateEpisodeNumber.present
        ? candidateEpisodeNumber.value
        : this.candidateEpisodeNumber,
    candidateDetails: candidateDetails.present
        ? candidateDetails.value
        : this.candidateDetails,
  );
  MediaFileData copyWithCompanion(MediaFilesCompanion data) {
    return MediaFileData(
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      container: data.container.present ? data.container.value : this.container,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      resolutionWidth: data.resolutionWidth.present
          ? data.resolutionWidth.value
          : this.resolutionWidth,
      resolutionHeight: data.resolutionHeight.present
          ? data.resolutionHeight.value
          : this.resolutionHeight,
      videoCodec: data.videoCodec.present
          ? data.videoCodec.value
          : this.videoCodec,
      audioCodec: data.audioCodec.present
          ? data.audioCodec.value
          : this.audioCodec,
      parseState: data.parseState.present
          ? data.parseState.value
          : this.parseState,
      candidateType: data.candidateType.present
          ? data.candidateType.value
          : this.candidateType,
      candidateSeasonNumber: data.candidateSeasonNumber.present
          ? data.candidateSeasonNumber.value
          : this.candidateSeasonNumber,
      candidateEpisodeNumber: data.candidateEpisodeNumber.present
          ? data.candidateEpisodeNumber.value
          : this.candidateEpisodeNumber,
      candidateDetails: data.candidateDetails.present
          ? data.candidateDetails.value
          : this.candidateDetails,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaFileData(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('container: $container, ')
          ..write('durationMs: $durationMs, ')
          ..write('resolutionWidth: $resolutionWidth, ')
          ..write('resolutionHeight: $resolutionHeight, ')
          ..write('videoCodec: $videoCodec, ')
          ..write('audioCodec: $audioCodec, ')
          ..write('parseState: $parseState, ')
          ..write('candidateType: $candidateType, ')
          ..write('candidateSeasonNumber: $candidateSeasonNumber, ')
          ..write('candidateEpisodeNumber: $candidateEpisodeNumber, ')
          ..write('candidateDetails: $candidateDetails')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entryId,
    container,
    durationMs,
    resolutionWidth,
    resolutionHeight,
    videoCodec,
    audioCodec,
    parseState,
    candidateType,
    candidateSeasonNumber,
    candidateEpisodeNumber,
    candidateDetails,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaFileData &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.container == this.container &&
          other.durationMs == this.durationMs &&
          other.resolutionWidth == this.resolutionWidth &&
          other.resolutionHeight == this.resolutionHeight &&
          other.videoCodec == this.videoCodec &&
          other.audioCodec == this.audioCodec &&
          other.parseState == this.parseState &&
          other.candidateType == this.candidateType &&
          other.candidateSeasonNumber == this.candidateSeasonNumber &&
          other.candidateEpisodeNumber == this.candidateEpisodeNumber &&
          other.candidateDetails == this.candidateDetails);
}

class MediaFilesCompanion extends UpdateCompanion<MediaFileData> {
  final Value<int> id;
  final Value<int> entryId;
  final Value<String?> container;
  final Value<int?> durationMs;
  final Value<int?> resolutionWidth;
  final Value<int?> resolutionHeight;
  final Value<String?> videoCodec;
  final Value<String?> audioCodec;
  final Value<String> parseState;
  final Value<String?> candidateType;
  final Value<int?> candidateSeasonNumber;
  final Value<int?> candidateEpisodeNumber;
  final Value<String?> candidateDetails;
  const MediaFilesCompanion({
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.container = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.resolutionWidth = const Value.absent(),
    this.resolutionHeight = const Value.absent(),
    this.videoCodec = const Value.absent(),
    this.audioCodec = const Value.absent(),
    this.parseState = const Value.absent(),
    this.candidateType = const Value.absent(),
    this.candidateSeasonNumber = const Value.absent(),
    this.candidateEpisodeNumber = const Value.absent(),
    this.candidateDetails = const Value.absent(),
  });
  MediaFilesCompanion.insert({
    this.id = const Value.absent(),
    required int entryId,
    this.container = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.resolutionWidth = const Value.absent(),
    this.resolutionHeight = const Value.absent(),
    this.videoCodec = const Value.absent(),
    this.audioCodec = const Value.absent(),
    this.parseState = const Value.absent(),
    this.candidateType = const Value.absent(),
    this.candidateSeasonNumber = const Value.absent(),
    this.candidateEpisodeNumber = const Value.absent(),
    this.candidateDetails = const Value.absent(),
  }) : entryId = Value(entryId);
  static Insertable<MediaFileData> custom({
    Expression<int>? id,
    Expression<int>? entryId,
    Expression<String>? container,
    Expression<int>? durationMs,
    Expression<int>? resolutionWidth,
    Expression<int>? resolutionHeight,
    Expression<String>? videoCodec,
    Expression<String>? audioCodec,
    Expression<String>? parseState,
    Expression<String>? candidateType,
    Expression<int>? candidateSeasonNumber,
    Expression<int>? candidateEpisodeNumber,
    Expression<String>? candidateDetails,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (container != null) 'container': container,
      if (durationMs != null) 'duration_ms': durationMs,
      if (resolutionWidth != null) 'resolution_width': resolutionWidth,
      if (resolutionHeight != null) 'resolution_height': resolutionHeight,
      if (videoCodec != null) 'video_codec': videoCodec,
      if (audioCodec != null) 'audio_codec': audioCodec,
      if (parseState != null) 'parse_state': parseState,
      if (candidateType != null) 'candidate_type': candidateType,
      if (candidateSeasonNumber != null)
        'candidate_season_number': candidateSeasonNumber,
      if (candidateEpisodeNumber != null)
        'candidate_episode_number': candidateEpisodeNumber,
      if (candidateDetails != null) 'candidate_details': candidateDetails,
    });
  }

  MediaFilesCompanion copyWith({
    Value<int>? id,
    Value<int>? entryId,
    Value<String?>? container,
    Value<int?>? durationMs,
    Value<int?>? resolutionWidth,
    Value<int?>? resolutionHeight,
    Value<String?>? videoCodec,
    Value<String?>? audioCodec,
    Value<String>? parseState,
    Value<String?>? candidateType,
    Value<int?>? candidateSeasonNumber,
    Value<int?>? candidateEpisodeNumber,
    Value<String?>? candidateDetails,
  }) {
    return MediaFilesCompanion(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      container: container ?? this.container,
      durationMs: durationMs ?? this.durationMs,
      resolutionWidth: resolutionWidth ?? this.resolutionWidth,
      resolutionHeight: resolutionHeight ?? this.resolutionHeight,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      parseState: parseState ?? this.parseState,
      candidateType: candidateType ?? this.candidateType,
      candidateSeasonNumber:
          candidateSeasonNumber ?? this.candidateSeasonNumber,
      candidateEpisodeNumber:
          candidateEpisodeNumber ?? this.candidateEpisodeNumber,
      candidateDetails: candidateDetails ?? this.candidateDetails,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<int>(entryId.value);
    }
    if (container.present) {
      map['container'] = Variable<String>(container.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (resolutionWidth.present) {
      map['resolution_width'] = Variable<int>(resolutionWidth.value);
    }
    if (resolutionHeight.present) {
      map['resolution_height'] = Variable<int>(resolutionHeight.value);
    }
    if (videoCodec.present) {
      map['video_codec'] = Variable<String>(videoCodec.value);
    }
    if (audioCodec.present) {
      map['audio_codec'] = Variable<String>(audioCodec.value);
    }
    if (parseState.present) {
      map['parse_state'] = Variable<String>(parseState.value);
    }
    if (candidateType.present) {
      map['candidate_type'] = Variable<String>(candidateType.value);
    }
    if (candidateSeasonNumber.present) {
      map['candidate_season_number'] = Variable<int>(
        candidateSeasonNumber.value,
      );
    }
    if (candidateEpisodeNumber.present) {
      map['candidate_episode_number'] = Variable<int>(
        candidateEpisodeNumber.value,
      );
    }
    if (candidateDetails.present) {
      map['candidate_details'] = Variable<String>(candidateDetails.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaFilesCompanion(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('container: $container, ')
          ..write('durationMs: $durationMs, ')
          ..write('resolutionWidth: $resolutionWidth, ')
          ..write('resolutionHeight: $resolutionHeight, ')
          ..write('videoCodec: $videoCodec, ')
          ..write('audioCodec: $audioCodec, ')
          ..write('parseState: $parseState, ')
          ..write('candidateType: $candidateType, ')
          ..write('candidateSeasonNumber: $candidateSeasonNumber, ')
          ..write('candidateEpisodeNumber: $candidateEpisodeNumber, ')
          ..write('candidateDetails: $candidateDetails')
          ..write(')'))
        .toString();
  }
}

class $WorksTable extends Works with TableInfo<$WorksTable, WorkData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalTitleMeta = const VerificationMeta(
    'originalTitle',
  );
  @override
  late final GeneratedColumn<String> originalTitle = GeneratedColumn<String>(
    'original_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _overviewMeta = const VerificationMeta(
    'overview',
  );
  @override
  late final GeneratedColumn<String> overview = GeneratedColumn<String>(
    'overview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _posterPathMeta = const VerificationMeta(
    'posterPath',
  );
  @override
  late final GeneratedColumn<String> posterPath = GeneratedColumn<String>(
    'poster_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backdropPathMeta = const VerificationMeta(
    'backdropPath',
  );
  @override
  late final GeneratedColumn<String> backdropPath = GeneratedColumn<String>(
    'backdrop_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _metadataSourceMeta = const VerificationMeta(
    'metadataSource',
  );
  @override
  late final GeneratedColumn<String> metadataSource = GeneratedColumn<String>(
    'metadata_source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  static const VerificationMeta _metadataLockedMeta = const VerificationMeta(
    'metadataLocked',
  );
  @override
  late final GeneratedColumn<bool> metadataLocked = GeneratedColumn<bool>(
    'metadata_locked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("metadata_locked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    title,
    originalTitle,
    year,
    overview,
    posterPath,
    backdropPath,
    metadataSource,
    metadataLocked,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'works';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('original_title')) {
      context.handle(
        _originalTitleMeta,
        originalTitle.isAcceptableOrUnknown(
          data['original_title']!,
          _originalTitleMeta,
        ),
      );
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('overview')) {
      context.handle(
        _overviewMeta,
        overview.isAcceptableOrUnknown(data['overview']!, _overviewMeta),
      );
    }
    if (data.containsKey('poster_path')) {
      context.handle(
        _posterPathMeta,
        posterPath.isAcceptableOrUnknown(data['poster_path']!, _posterPathMeta),
      );
    }
    if (data.containsKey('backdrop_path')) {
      context.handle(
        _backdropPathMeta,
        backdropPath.isAcceptableOrUnknown(
          data['backdrop_path']!,
          _backdropPathMeta,
        ),
      );
    }
    if (data.containsKey('metadata_source')) {
      context.handle(
        _metadataSourceMeta,
        metadataSource.isAcceptableOrUnknown(
          data['metadata_source']!,
          _metadataSourceMeta,
        ),
      );
    }
    if (data.containsKey('metadata_locked')) {
      context.handle(
        _metadataLockedMeta,
        metadataLocked.isAcceptableOrUnknown(
          data['metadata_locked']!,
          _metadataLockedMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      originalTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_title'],
      ),
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      overview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overview'],
      ),
      posterPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster_path'],
      ),
      backdropPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backdrop_path'],
      ),
      metadataSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_source'],
      )!,
      metadataLocked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}metadata_locked'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WorksTable createAlias(String alias) {
    return $WorksTable(attachedDatabase, alias);
  }
}

class WorkData extends DataClass implements Insertable<WorkData> {
  final int id;
  final String? type;
  final String title;
  final String? originalTitle;
  final int? year;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String metadataSource;
  final bool metadataLocked;
  final DateTime createdAt;
  final DateTime updatedAt;
  const WorkData({
    required this.id,
    this.type,
    required this.title,
    this.originalTitle,
    this.year,
    this.overview,
    this.posterPath,
    this.backdropPath,
    required this.metadataSource,
    required this.metadataLocked,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || type != null) {
      map['type'] = Variable<String>(type);
    }
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || originalTitle != null) {
      map['original_title'] = Variable<String>(originalTitle);
    }
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || overview != null) {
      map['overview'] = Variable<String>(overview);
    }
    if (!nullToAbsent || posterPath != null) {
      map['poster_path'] = Variable<String>(posterPath);
    }
    if (!nullToAbsent || backdropPath != null) {
      map['backdrop_path'] = Variable<String>(backdropPath);
    }
    map['metadata_source'] = Variable<String>(metadataSource);
    map['metadata_locked'] = Variable<bool>(metadataLocked);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WorksCompanion toCompanion(bool nullToAbsent) {
    return WorksCompanion(
      id: Value(id),
      type: type == null && nullToAbsent ? const Value.absent() : Value(type),
      title: Value(title),
      originalTitle: originalTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(originalTitle),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      overview: overview == null && nullToAbsent
          ? const Value.absent()
          : Value(overview),
      posterPath: posterPath == null && nullToAbsent
          ? const Value.absent()
          : Value(posterPath),
      backdropPath: backdropPath == null && nullToAbsent
          ? const Value.absent()
          : Value(backdropPath),
      metadataSource: Value(metadataSource),
      metadataLocked: Value(metadataLocked),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory WorkData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkData(
      id: serializer.fromJson<int>(json['id']),
      type: serializer.fromJson<String?>(json['type']),
      title: serializer.fromJson<String>(json['title']),
      originalTitle: serializer.fromJson<String?>(json['originalTitle']),
      year: serializer.fromJson<int?>(json['year']),
      overview: serializer.fromJson<String?>(json['overview']),
      posterPath: serializer.fromJson<String?>(json['posterPath']),
      backdropPath: serializer.fromJson<String?>(json['backdropPath']),
      metadataSource: serializer.fromJson<String>(json['metadataSource']),
      metadataLocked: serializer.fromJson<bool>(json['metadataLocked']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String?>(type),
      'title': serializer.toJson<String>(title),
      'originalTitle': serializer.toJson<String?>(originalTitle),
      'year': serializer.toJson<int?>(year),
      'overview': serializer.toJson<String?>(overview),
      'posterPath': serializer.toJson<String?>(posterPath),
      'backdropPath': serializer.toJson<String?>(backdropPath),
      'metadataSource': serializer.toJson<String>(metadataSource),
      'metadataLocked': serializer.toJson<bool>(metadataLocked),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WorkData copyWith({
    int? id,
    Value<String?> type = const Value.absent(),
    String? title,
    Value<String?> originalTitle = const Value.absent(),
    Value<int?> year = const Value.absent(),
    Value<String?> overview = const Value.absent(),
    Value<String?> posterPath = const Value.absent(),
    Value<String?> backdropPath = const Value.absent(),
    String? metadataSource,
    bool? metadataLocked,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WorkData(
    id: id ?? this.id,
    type: type.present ? type.value : this.type,
    title: title ?? this.title,
    originalTitle: originalTitle.present
        ? originalTitle.value
        : this.originalTitle,
    year: year.present ? year.value : this.year,
    overview: overview.present ? overview.value : this.overview,
    posterPath: posterPath.present ? posterPath.value : this.posterPath,
    backdropPath: backdropPath.present ? backdropPath.value : this.backdropPath,
    metadataSource: metadataSource ?? this.metadataSource,
    metadataLocked: metadataLocked ?? this.metadataLocked,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WorkData copyWithCompanion(WorksCompanion data) {
    return WorkData(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      title: data.title.present ? data.title.value : this.title,
      originalTitle: data.originalTitle.present
          ? data.originalTitle.value
          : this.originalTitle,
      year: data.year.present ? data.year.value : this.year,
      overview: data.overview.present ? data.overview.value : this.overview,
      posterPath: data.posterPath.present
          ? data.posterPath.value
          : this.posterPath,
      backdropPath: data.backdropPath.present
          ? data.backdropPath.value
          : this.backdropPath,
      metadataSource: data.metadataSource.present
          ? data.metadataSource.value
          : this.metadataSource,
      metadataLocked: data.metadataLocked.present
          ? data.metadataLocked.value
          : this.metadataLocked,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkData(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('originalTitle: $originalTitle, ')
          ..write('year: $year, ')
          ..write('overview: $overview, ')
          ..write('posterPath: $posterPath, ')
          ..write('backdropPath: $backdropPath, ')
          ..write('metadataSource: $metadataSource, ')
          ..write('metadataLocked: $metadataLocked, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    title,
    originalTitle,
    year,
    overview,
    posterPath,
    backdropPath,
    metadataSource,
    metadataLocked,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkData &&
          other.id == this.id &&
          other.type == this.type &&
          other.title == this.title &&
          other.originalTitle == this.originalTitle &&
          other.year == this.year &&
          other.overview == this.overview &&
          other.posterPath == this.posterPath &&
          other.backdropPath == this.backdropPath &&
          other.metadataSource == this.metadataSource &&
          other.metadataLocked == this.metadataLocked &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class WorksCompanion extends UpdateCompanion<WorkData> {
  final Value<int> id;
  final Value<String?> type;
  final Value<String> title;
  final Value<String?> originalTitle;
  final Value<int?> year;
  final Value<String?> overview;
  final Value<String?> posterPath;
  final Value<String?> backdropPath;
  final Value<String> metadataSource;
  final Value<bool> metadataLocked;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const WorksCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.originalTitle = const Value.absent(),
    this.year = const Value.absent(),
    this.overview = const Value.absent(),
    this.posterPath = const Value.absent(),
    this.backdropPath = const Value.absent(),
    this.metadataSource = const Value.absent(),
    this.metadataLocked = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  WorksCompanion.insert({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    required String title,
    this.originalTitle = const Value.absent(),
    this.year = const Value.absent(),
    this.overview = const Value.absent(),
    this.posterPath = const Value.absent(),
    this.backdropPath = const Value.absent(),
    this.metadataSource = const Value.absent(),
    this.metadataLocked = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : title = Value(title);
  static Insertable<WorkData> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? originalTitle,
    Expression<int>? year,
    Expression<String>? overview,
    Expression<String>? posterPath,
    Expression<String>? backdropPath,
    Expression<String>? metadataSource,
    Expression<bool>? metadataLocked,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (originalTitle != null) 'original_title': originalTitle,
      if (year != null) 'year': year,
      if (overview != null) 'overview': overview,
      if (posterPath != null) 'poster_path': posterPath,
      if (backdropPath != null) 'backdrop_path': backdropPath,
      if (metadataSource != null) 'metadata_source': metadataSource,
      if (metadataLocked != null) 'metadata_locked': metadataLocked,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  WorksCompanion copyWith({
    Value<int>? id,
    Value<String?>? type,
    Value<String>? title,
    Value<String?>? originalTitle,
    Value<int?>? year,
    Value<String?>? overview,
    Value<String?>? posterPath,
    Value<String?>? backdropPath,
    Value<String>? metadataSource,
    Value<bool>? metadataLocked,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return WorksCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      year: year ?? this.year,
      overview: overview ?? this.overview,
      posterPath: posterPath ?? this.posterPath,
      backdropPath: backdropPath ?? this.backdropPath,
      metadataSource: metadataSource ?? this.metadataSource,
      metadataLocked: metadataLocked ?? this.metadataLocked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (originalTitle.present) {
      map['original_title'] = Variable<String>(originalTitle.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (overview.present) {
      map['overview'] = Variable<String>(overview.value);
    }
    if (posterPath.present) {
      map['poster_path'] = Variable<String>(posterPath.value);
    }
    if (backdropPath.present) {
      map['backdrop_path'] = Variable<String>(backdropPath.value);
    }
    if (metadataSource.present) {
      map['metadata_source'] = Variable<String>(metadataSource.value);
    }
    if (metadataLocked.present) {
      map['metadata_locked'] = Variable<bool>(metadataLocked.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorksCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('originalTitle: $originalTitle, ')
          ..write('year: $year, ')
          ..write('overview: $overview, ')
          ..write('posterPath: $posterPath, ')
          ..write('backdropPath: $backdropPath, ')
          ..write('metadataSource: $metadataSource, ')
          ..write('metadataLocked: $metadataLocked, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $SeasonsTable extends Seasons with TableInfo<$SeasonsTable, SeasonData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeasonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<int> seriesId = GeneratedColumn<int>(
    'series_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES works (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _seasonNumberMeta = const VerificationMeta(
    'seasonNumber',
  );
  @override
  late final GeneratedColumn<int> seasonNumber = GeneratedColumn<int>(
    'season_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, seriesId, seasonNumber, title];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'seasons';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeasonData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesIdMeta);
    }
    if (data.containsKey('season_number')) {
      context.handle(
        _seasonNumberMeta,
        seasonNumber.isAcceptableOrUnknown(
          data['season_number']!,
          _seasonNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_seasonNumberMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {seriesId, seasonNumber},
  ];
  @override
  SeasonData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeasonData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}series_id'],
      )!,
      seasonNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_number'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
    );
  }

  @override
  $SeasonsTable createAlias(String alias) {
    return $SeasonsTable(attachedDatabase, alias);
  }
}

class SeasonData extends DataClass implements Insertable<SeasonData> {
  final int id;
  final int seriesId;
  final int seasonNumber;
  final String? title;
  const SeasonData({
    required this.id,
    required this.seriesId,
    required this.seasonNumber,
    this.title,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['series_id'] = Variable<int>(seriesId);
    map['season_number'] = Variable<int>(seasonNumber);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    return map;
  }

  SeasonsCompanion toCompanion(bool nullToAbsent) {
    return SeasonsCompanion(
      id: Value(id),
      seriesId: Value(seriesId),
      seasonNumber: Value(seasonNumber),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
    );
  }

  factory SeasonData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeasonData(
      id: serializer.fromJson<int>(json['id']),
      seriesId: serializer.fromJson<int>(json['seriesId']),
      seasonNumber: serializer.fromJson<int>(json['seasonNumber']),
      title: serializer.fromJson<String?>(json['title']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'seriesId': serializer.toJson<int>(seriesId),
      'seasonNumber': serializer.toJson<int>(seasonNumber),
      'title': serializer.toJson<String?>(title),
    };
  }

  SeasonData copyWith({
    int? id,
    int? seriesId,
    int? seasonNumber,
    Value<String?> title = const Value.absent(),
  }) => SeasonData(
    id: id ?? this.id,
    seriesId: seriesId ?? this.seriesId,
    seasonNumber: seasonNumber ?? this.seasonNumber,
    title: title.present ? title.value : this.title,
  );
  SeasonData copyWithCompanion(SeasonsCompanion data) {
    return SeasonData(
      id: data.id.present ? data.id.value : this.id,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      seasonNumber: data.seasonNumber.present
          ? data.seasonNumber.value
          : this.seasonNumber,
      title: data.title.present ? data.title.value : this.title,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeasonData(')
          ..write('id: $id, ')
          ..write('seriesId: $seriesId, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, seriesId, seasonNumber, title);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeasonData &&
          other.id == this.id &&
          other.seriesId == this.seriesId &&
          other.seasonNumber == this.seasonNumber &&
          other.title == this.title);
}

class SeasonsCompanion extends UpdateCompanion<SeasonData> {
  final Value<int> id;
  final Value<int> seriesId;
  final Value<int> seasonNumber;
  final Value<String?> title;
  const SeasonsCompanion({
    this.id = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.seasonNumber = const Value.absent(),
    this.title = const Value.absent(),
  });
  SeasonsCompanion.insert({
    this.id = const Value.absent(),
    required int seriesId,
    required int seasonNumber,
    this.title = const Value.absent(),
  }) : seriesId = Value(seriesId),
       seasonNumber = Value(seasonNumber);
  static Insertable<SeasonData> custom({
    Expression<int>? id,
    Expression<int>? seriesId,
    Expression<int>? seasonNumber,
    Expression<String>? title,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seriesId != null) 'series_id': seriesId,
      if (seasonNumber != null) 'season_number': seasonNumber,
      if (title != null) 'title': title,
    });
  }

  SeasonsCompanion copyWith({
    Value<int>? id,
    Value<int>? seriesId,
    Value<int>? seasonNumber,
    Value<String?>? title,
  }) {
    return SeasonsCompanion(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      title: title ?? this.title,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<int>(seriesId.value);
    }
    if (seasonNumber.present) {
      map['season_number'] = Variable<int>(seasonNumber.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeasonsCompanion(')
          ..write('id: $id, ')
          ..write('seriesId: $seriesId, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }
}

class $EpisodesTable extends Episodes
    with TableInfo<$EpisodesTable, EpisodeData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpisodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _seasonIdMeta = const VerificationMeta(
    'seasonId',
  );
  @override
  late final GeneratedColumn<int> seasonId = GeneratedColumn<int>(
    'season_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES seasons (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _episodeNumberMeta = const VerificationMeta(
    'episodeNumber',
  );
  @override
  late final GeneratedColumn<int> episodeNumber = GeneratedColumn<int>(
    'episode_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _overviewMeta = const VerificationMeta(
    'overview',
  );
  @override
  late final GeneratedColumn<String> overview = GeneratedColumn<String>(
    'overview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _airDateMeta = const VerificationMeta(
    'airDate',
  );
  @override
  late final GeneratedColumn<DateTime> airDate = GeneratedColumn<DateTime>(
    'air_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    seasonId,
    episodeNumber,
    title,
    overview,
    airDate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'episodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<EpisodeData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('season_id')) {
      context.handle(
        _seasonIdMeta,
        seasonId.isAcceptableOrUnknown(data['season_id']!, _seasonIdMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonIdMeta);
    }
    if (data.containsKey('episode_number')) {
      context.handle(
        _episodeNumberMeta,
        episodeNumber.isAcceptableOrUnknown(
          data['episode_number']!,
          _episodeNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_episodeNumberMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('overview')) {
      context.handle(
        _overviewMeta,
        overview.isAcceptableOrUnknown(data['overview']!, _overviewMeta),
      );
    }
    if (data.containsKey('air_date')) {
      context.handle(
        _airDateMeta,
        airDate.isAcceptableOrUnknown(data['air_date']!, _airDateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {seasonId, episodeNumber},
  ];
  @override
  EpisodeData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpisodeData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      seasonId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_id'],
      )!,
      episodeNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_number'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      overview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overview'],
      ),
      airDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}air_date'],
      ),
    );
  }

  @override
  $EpisodesTable createAlias(String alias) {
    return $EpisodesTable(attachedDatabase, alias);
  }
}

class EpisodeData extends DataClass implements Insertable<EpisodeData> {
  final int id;
  final int seasonId;
  final int episodeNumber;
  final String? title;
  final String? overview;
  final DateTime? airDate;
  const EpisodeData({
    required this.id,
    required this.seasonId,
    required this.episodeNumber,
    this.title,
    this.overview,
    this.airDate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['season_id'] = Variable<int>(seasonId);
    map['episode_number'] = Variable<int>(episodeNumber);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || overview != null) {
      map['overview'] = Variable<String>(overview);
    }
    if (!nullToAbsent || airDate != null) {
      map['air_date'] = Variable<DateTime>(airDate);
    }
    return map;
  }

  EpisodesCompanion toCompanion(bool nullToAbsent) {
    return EpisodesCompanion(
      id: Value(id),
      seasonId: Value(seasonId),
      episodeNumber: Value(episodeNumber),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      overview: overview == null && nullToAbsent
          ? const Value.absent()
          : Value(overview),
      airDate: airDate == null && nullToAbsent
          ? const Value.absent()
          : Value(airDate),
    );
  }

  factory EpisodeData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpisodeData(
      id: serializer.fromJson<int>(json['id']),
      seasonId: serializer.fromJson<int>(json['seasonId']),
      episodeNumber: serializer.fromJson<int>(json['episodeNumber']),
      title: serializer.fromJson<String?>(json['title']),
      overview: serializer.fromJson<String?>(json['overview']),
      airDate: serializer.fromJson<DateTime?>(json['airDate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'seasonId': serializer.toJson<int>(seasonId),
      'episodeNumber': serializer.toJson<int>(episodeNumber),
      'title': serializer.toJson<String?>(title),
      'overview': serializer.toJson<String?>(overview),
      'airDate': serializer.toJson<DateTime?>(airDate),
    };
  }

  EpisodeData copyWith({
    int? id,
    int? seasonId,
    int? episodeNumber,
    Value<String?> title = const Value.absent(),
    Value<String?> overview = const Value.absent(),
    Value<DateTime?> airDate = const Value.absent(),
  }) => EpisodeData(
    id: id ?? this.id,
    seasonId: seasonId ?? this.seasonId,
    episodeNumber: episodeNumber ?? this.episodeNumber,
    title: title.present ? title.value : this.title,
    overview: overview.present ? overview.value : this.overview,
    airDate: airDate.present ? airDate.value : this.airDate,
  );
  EpisodeData copyWithCompanion(EpisodesCompanion data) {
    return EpisodeData(
      id: data.id.present ? data.id.value : this.id,
      seasonId: data.seasonId.present ? data.seasonId.value : this.seasonId,
      episodeNumber: data.episodeNumber.present
          ? data.episodeNumber.value
          : this.episodeNumber,
      title: data.title.present ? data.title.value : this.title,
      overview: data.overview.present ? data.overview.value : this.overview,
      airDate: data.airDate.present ? data.airDate.value : this.airDate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpisodeData(')
          ..write('id: $id, ')
          ..write('seasonId: $seasonId, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('title: $title, ')
          ..write('overview: $overview, ')
          ..write('airDate: $airDate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, seasonId, episodeNumber, title, overview, airDate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpisodeData &&
          other.id == this.id &&
          other.seasonId == this.seasonId &&
          other.episodeNumber == this.episodeNumber &&
          other.title == this.title &&
          other.overview == this.overview &&
          other.airDate == this.airDate);
}

class EpisodesCompanion extends UpdateCompanion<EpisodeData> {
  final Value<int> id;
  final Value<int> seasonId;
  final Value<int> episodeNumber;
  final Value<String?> title;
  final Value<String?> overview;
  final Value<DateTime?> airDate;
  const EpisodesCompanion({
    this.id = const Value.absent(),
    this.seasonId = const Value.absent(),
    this.episodeNumber = const Value.absent(),
    this.title = const Value.absent(),
    this.overview = const Value.absent(),
    this.airDate = const Value.absent(),
  });
  EpisodesCompanion.insert({
    this.id = const Value.absent(),
    required int seasonId,
    required int episodeNumber,
    this.title = const Value.absent(),
    this.overview = const Value.absent(),
    this.airDate = const Value.absent(),
  }) : seasonId = Value(seasonId),
       episodeNumber = Value(episodeNumber);
  static Insertable<EpisodeData> custom({
    Expression<int>? id,
    Expression<int>? seasonId,
    Expression<int>? episodeNumber,
    Expression<String>? title,
    Expression<String>? overview,
    Expression<DateTime>? airDate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (seasonId != null) 'season_id': seasonId,
      if (episodeNumber != null) 'episode_number': episodeNumber,
      if (title != null) 'title': title,
      if (overview != null) 'overview': overview,
      if (airDate != null) 'air_date': airDate,
    });
  }

  EpisodesCompanion copyWith({
    Value<int>? id,
    Value<int>? seasonId,
    Value<int>? episodeNumber,
    Value<String?>? title,
    Value<String?>? overview,
    Value<DateTime?>? airDate,
  }) {
    return EpisodesCompanion(
      id: id ?? this.id,
      seasonId: seasonId ?? this.seasonId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      title: title ?? this.title,
      overview: overview ?? this.overview,
      airDate: airDate ?? this.airDate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (seasonId.present) {
      map['season_id'] = Variable<int>(seasonId.value);
    }
    if (episodeNumber.present) {
      map['episode_number'] = Variable<int>(episodeNumber.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (overview.present) {
      map['overview'] = Variable<String>(overview.value);
    }
    if (airDate.present) {
      map['air_date'] = Variable<DateTime>(airDate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpisodesCompanion(')
          ..write('id: $id, ')
          ..write('seasonId: $seasonId, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('title: $title, ')
          ..write('overview: $overview, ')
          ..write('airDate: $airDate')
          ..write(')'))
        .toString();
  }
}

class $MediaAssignmentsTable extends MediaAssignments
    with TableInfo<$MediaAssignmentsTable, MediaAssignmentData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaAssignmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<int> fileId = GeneratedColumn<int>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES media_files (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<int> workId = GeneratedColumn<int>(
    'work_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES works (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _episodeIdMeta = const VerificationMeta(
    'episodeId',
  );
  @override
  late final GeneratedColumn<int> episodeId = GeneratedColumn<int>(
    'episode_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES episodes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _editionLabelMeta = const VerificationMeta(
    'editionLabel',
  );
  @override
  late final GeneratedColumn<String> editionLabel = GeneratedColumn<String>(
    'edition_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _preferredMeta = const VerificationMeta(
    'preferred',
  );
  @override
  late final GeneratedColumn<bool> preferred = GeneratedColumn<bool>(
    'preferred',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("preferred" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fileId,
    workId,
    episodeId,
    editionLabel,
    preferred,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_assignments';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaAssignmentData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    }
    if (data.containsKey('episode_id')) {
      context.handle(
        _episodeIdMeta,
        episodeId.isAcceptableOrUnknown(data['episode_id']!, _episodeIdMeta),
      );
    }
    if (data.containsKey('edition_label')) {
      context.handle(
        _editionLabelMeta,
        editionLabel.isAcceptableOrUnknown(
          data['edition_label']!,
          _editionLabelMeta,
        ),
      );
    }
    if (data.containsKey('preferred')) {
      context.handle(
        _preferredMeta,
        preferred.isAcceptableOrUnknown(data['preferred']!, _preferredMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaAssignmentData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaAssignmentData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_id'],
      )!,
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}work_id'],
      ),
      episodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_id'],
      ),
      editionLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}edition_label'],
      ),
      preferred: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}preferred'],
      )!,
    );
  }

  @override
  $MediaAssignmentsTable createAlias(String alias) {
    return $MediaAssignmentsTable(attachedDatabase, alias);
  }
}

class MediaAssignmentData extends DataClass
    implements Insertable<MediaAssignmentData> {
  final int id;
  final int fileId;
  final int? workId;
  final int? episodeId;
  final String? editionLabel;
  final bool preferred;
  const MediaAssignmentData({
    required this.id,
    required this.fileId,
    this.workId,
    this.episodeId,
    this.editionLabel,
    required this.preferred,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['file_id'] = Variable<int>(fileId);
    if (!nullToAbsent || workId != null) {
      map['work_id'] = Variable<int>(workId);
    }
    if (!nullToAbsent || episodeId != null) {
      map['episode_id'] = Variable<int>(episodeId);
    }
    if (!nullToAbsent || editionLabel != null) {
      map['edition_label'] = Variable<String>(editionLabel);
    }
    map['preferred'] = Variable<bool>(preferred);
    return map;
  }

  MediaAssignmentsCompanion toCompanion(bool nullToAbsent) {
    return MediaAssignmentsCompanion(
      id: Value(id),
      fileId: Value(fileId),
      workId: workId == null && nullToAbsent
          ? const Value.absent()
          : Value(workId),
      episodeId: episodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeId),
      editionLabel: editionLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(editionLabel),
      preferred: Value(preferred),
    );
  }

  factory MediaAssignmentData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaAssignmentData(
      id: serializer.fromJson<int>(json['id']),
      fileId: serializer.fromJson<int>(json['fileId']),
      workId: serializer.fromJson<int?>(json['workId']),
      episodeId: serializer.fromJson<int?>(json['episodeId']),
      editionLabel: serializer.fromJson<String?>(json['editionLabel']),
      preferred: serializer.fromJson<bool>(json['preferred']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fileId': serializer.toJson<int>(fileId),
      'workId': serializer.toJson<int?>(workId),
      'episodeId': serializer.toJson<int?>(episodeId),
      'editionLabel': serializer.toJson<String?>(editionLabel),
      'preferred': serializer.toJson<bool>(preferred),
    };
  }

  MediaAssignmentData copyWith({
    int? id,
    int? fileId,
    Value<int?> workId = const Value.absent(),
    Value<int?> episodeId = const Value.absent(),
    Value<String?> editionLabel = const Value.absent(),
    bool? preferred,
  }) => MediaAssignmentData(
    id: id ?? this.id,
    fileId: fileId ?? this.fileId,
    workId: workId.present ? workId.value : this.workId,
    episodeId: episodeId.present ? episodeId.value : this.episodeId,
    editionLabel: editionLabel.present ? editionLabel.value : this.editionLabel,
    preferred: preferred ?? this.preferred,
  );
  MediaAssignmentData copyWithCompanion(MediaAssignmentsCompanion data) {
    return MediaAssignmentData(
      id: data.id.present ? data.id.value : this.id,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      workId: data.workId.present ? data.workId.value : this.workId,
      episodeId: data.episodeId.present ? data.episodeId.value : this.episodeId,
      editionLabel: data.editionLabel.present
          ? data.editionLabel.value
          : this.editionLabel,
      preferred: data.preferred.present ? data.preferred.value : this.preferred,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaAssignmentData(')
          ..write('id: $id, ')
          ..write('fileId: $fileId, ')
          ..write('workId: $workId, ')
          ..write('episodeId: $episodeId, ')
          ..write('editionLabel: $editionLabel, ')
          ..write('preferred: $preferred')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, fileId, workId, episodeId, editionLabel, preferred);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaAssignmentData &&
          other.id == this.id &&
          other.fileId == this.fileId &&
          other.workId == this.workId &&
          other.episodeId == this.episodeId &&
          other.editionLabel == this.editionLabel &&
          other.preferred == this.preferred);
}

class MediaAssignmentsCompanion extends UpdateCompanion<MediaAssignmentData> {
  final Value<int> id;
  final Value<int> fileId;
  final Value<int?> workId;
  final Value<int?> episodeId;
  final Value<String?> editionLabel;
  final Value<bool> preferred;
  const MediaAssignmentsCompanion({
    this.id = const Value.absent(),
    this.fileId = const Value.absent(),
    this.workId = const Value.absent(),
    this.episodeId = const Value.absent(),
    this.editionLabel = const Value.absent(),
    this.preferred = const Value.absent(),
  });
  MediaAssignmentsCompanion.insert({
    this.id = const Value.absent(),
    required int fileId,
    this.workId = const Value.absent(),
    this.episodeId = const Value.absent(),
    this.editionLabel = const Value.absent(),
    this.preferred = const Value.absent(),
  }) : fileId = Value(fileId);
  static Insertable<MediaAssignmentData> custom({
    Expression<int>? id,
    Expression<int>? fileId,
    Expression<int>? workId,
    Expression<int>? episodeId,
    Expression<String>? editionLabel,
    Expression<bool>? preferred,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fileId != null) 'file_id': fileId,
      if (workId != null) 'work_id': workId,
      if (episodeId != null) 'episode_id': episodeId,
      if (editionLabel != null) 'edition_label': editionLabel,
      if (preferred != null) 'preferred': preferred,
    });
  }

  MediaAssignmentsCompanion copyWith({
    Value<int>? id,
    Value<int>? fileId,
    Value<int?>? workId,
    Value<int?>? episodeId,
    Value<String?>? editionLabel,
    Value<bool>? preferred,
  }) {
    return MediaAssignmentsCompanion(
      id: id ?? this.id,
      fileId: fileId ?? this.fileId,
      workId: workId ?? this.workId,
      episodeId: episodeId ?? this.episodeId,
      editionLabel: editionLabel ?? this.editionLabel,
      preferred: preferred ?? this.preferred,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fileId.present) {
      map['file_id'] = Variable<int>(fileId.value);
    }
    if (workId.present) {
      map['work_id'] = Variable<int>(workId.value);
    }
    if (episodeId.present) {
      map['episode_id'] = Variable<int>(episodeId.value);
    }
    if (editionLabel.present) {
      map['edition_label'] = Variable<String>(editionLabel.value);
    }
    if (preferred.present) {
      map['preferred'] = Variable<bool>(preferred.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaAssignmentsCompanion(')
          ..write('id: $id, ')
          ..write('fileId: $fileId, ')
          ..write('workId: $workId, ')
          ..write('episodeId: $episodeId, ')
          ..write('editionLabel: $editionLabel, ')
          ..write('preferred: $preferred')
          ..write(')'))
        .toString();
  }
}

class $PlaybackProgressesTable extends PlaybackProgresses
    with TableInfo<$PlaybackProgressesTable, PlaybackProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackProgressesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _targetTypeMeta = const VerificationMeta(
    'targetType',
  );
  @override
  late final GeneratedColumn<String> targetType = GeneratedColumn<String>(
    'target_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<int> targetId = GeneratedColumn<int>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<int> workId = GeneratedColumn<int>(
    'work_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES works (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _episodeIdMeta = const VerificationMeta(
    'episodeId',
  );
  @override
  late final GeneratedColumn<int> episodeId = GeneratedColumn<int>(
    'episode_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES episodes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _lastFileIdMeta = const VerificationMeta(
    'lastFileId',
  );
  @override
  late final GeneratedColumn<int> lastFileId = GeneratedColumn<int>(
    'last_file_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES media_files (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    targetType,
    targetId,
    workId,
    episodeId,
    lastFileId,
    positionMs,
    durationMs,
    completed,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaybackProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('target_type')) {
      context.handle(
        _targetTypeMeta,
        targetType.isAcceptableOrUnknown(data['target_type']!, _targetTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_targetTypeMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    }
    if (data.containsKey('episode_id')) {
      context.handle(
        _episodeIdMeta,
        episodeId.isAcceptableOrUnknown(data['episode_id']!, _episodeIdMeta),
      );
    }
    if (data.containsKey('last_file_id')) {
      context.handle(
        _lastFileIdMeta,
        lastFileId.isAcceptableOrUnknown(
          data['last_file_id']!,
          _lastFileIdMeta,
        ),
      );
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {targetType, targetId},
  ];
  @override
  PlaybackProgressData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackProgressData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      targetType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_type'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_id'],
      )!,
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}work_id'],
      ),
      episodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_id'],
      ),
      lastFileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_file_id'],
      ),
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlaybackProgressesTable createAlias(String alias) {
    return $PlaybackProgressesTable(attachedDatabase, alias);
  }
}

class PlaybackProgressData extends DataClass
    implements Insertable<PlaybackProgressData> {
  final int id;
  final String targetType;
  final int targetId;
  final int? workId;
  final int? episodeId;
  final int? lastFileId;
  final int positionMs;
  final int durationMs;
  final bool completed;
  final DateTime updatedAt;
  const PlaybackProgressData({
    required this.id,
    required this.targetType,
    required this.targetId,
    this.workId,
    this.episodeId,
    this.lastFileId,
    required this.positionMs,
    required this.durationMs,
    required this.completed,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['target_type'] = Variable<String>(targetType);
    map['target_id'] = Variable<int>(targetId);
    if (!nullToAbsent || workId != null) {
      map['work_id'] = Variable<int>(workId);
    }
    if (!nullToAbsent || episodeId != null) {
      map['episode_id'] = Variable<int>(episodeId);
    }
    if (!nullToAbsent || lastFileId != null) {
      map['last_file_id'] = Variable<int>(lastFileId);
    }
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['completed'] = Variable<bool>(completed);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlaybackProgressesCompanion toCompanion(bool nullToAbsent) {
    return PlaybackProgressesCompanion(
      id: Value(id),
      targetType: Value(targetType),
      targetId: Value(targetId),
      workId: workId == null && nullToAbsent
          ? const Value.absent()
          : Value(workId),
      episodeId: episodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeId),
      lastFileId: lastFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFileId),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      completed: Value(completed),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlaybackProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackProgressData(
      id: serializer.fromJson<int>(json['id']),
      targetType: serializer.fromJson<String>(json['targetType']),
      targetId: serializer.fromJson<int>(json['targetId']),
      workId: serializer.fromJson<int?>(json['workId']),
      episodeId: serializer.fromJson<int?>(json['episodeId']),
      lastFileId: serializer.fromJson<int?>(json['lastFileId']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      completed: serializer.fromJson<bool>(json['completed']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'targetType': serializer.toJson<String>(targetType),
      'targetId': serializer.toJson<int>(targetId),
      'workId': serializer.toJson<int?>(workId),
      'episodeId': serializer.toJson<int?>(episodeId),
      'lastFileId': serializer.toJson<int?>(lastFileId),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'completed': serializer.toJson<bool>(completed),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlaybackProgressData copyWith({
    int? id,
    String? targetType,
    int? targetId,
    Value<int?> workId = const Value.absent(),
    Value<int?> episodeId = const Value.absent(),
    Value<int?> lastFileId = const Value.absent(),
    int? positionMs,
    int? durationMs,
    bool? completed,
    DateTime? updatedAt,
  }) => PlaybackProgressData(
    id: id ?? this.id,
    targetType: targetType ?? this.targetType,
    targetId: targetId ?? this.targetId,
    workId: workId.present ? workId.value : this.workId,
    episodeId: episodeId.present ? episodeId.value : this.episodeId,
    lastFileId: lastFileId.present ? lastFileId.value : this.lastFileId,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    completed: completed ?? this.completed,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlaybackProgressData copyWithCompanion(PlaybackProgressesCompanion data) {
    return PlaybackProgressData(
      id: data.id.present ? data.id.value : this.id,
      targetType: data.targetType.present
          ? data.targetType.value
          : this.targetType,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      workId: data.workId.present ? data.workId.value : this.workId,
      episodeId: data.episodeId.present ? data.episodeId.value : this.episodeId,
      lastFileId: data.lastFileId.present
          ? data.lastFileId.value
          : this.lastFileId,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      completed: data.completed.present ? data.completed.value : this.completed,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackProgressData(')
          ..write('id: $id, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('workId: $workId, ')
          ..write('episodeId: $episodeId, ')
          ..write('lastFileId: $lastFileId, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('completed: $completed, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    targetType,
    targetId,
    workId,
    episodeId,
    lastFileId,
    positionMs,
    durationMs,
    completed,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackProgressData &&
          other.id == this.id &&
          other.targetType == this.targetType &&
          other.targetId == this.targetId &&
          other.workId == this.workId &&
          other.episodeId == this.episodeId &&
          other.lastFileId == this.lastFileId &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.completed == this.completed &&
          other.updatedAt == this.updatedAt);
}

class PlaybackProgressesCompanion
    extends UpdateCompanion<PlaybackProgressData> {
  final Value<int> id;
  final Value<String> targetType;
  final Value<int> targetId;
  final Value<int?> workId;
  final Value<int?> episodeId;
  final Value<int?> lastFileId;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<bool> completed;
  final Value<DateTime> updatedAt;
  const PlaybackProgressesCompanion({
    this.id = const Value.absent(),
    this.targetType = const Value.absent(),
    this.targetId = const Value.absent(),
    this.workId = const Value.absent(),
    this.episodeId = const Value.absent(),
    this.lastFileId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.completed = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PlaybackProgressesCompanion.insert({
    this.id = const Value.absent(),
    required String targetType,
    required int targetId,
    this.workId = const Value.absent(),
    this.episodeId = const Value.absent(),
    this.lastFileId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.completed = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : targetType = Value(targetType),
       targetId = Value(targetId);
  static Insertable<PlaybackProgressData> custom({
    Expression<int>? id,
    Expression<String>? targetType,
    Expression<int>? targetId,
    Expression<int>? workId,
    Expression<int>? episodeId,
    Expression<int>? lastFileId,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<bool>? completed,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (targetType != null) 'target_type': targetType,
      if (targetId != null) 'target_id': targetId,
      if (workId != null) 'work_id': workId,
      if (episodeId != null) 'episode_id': episodeId,
      if (lastFileId != null) 'last_file_id': lastFileId,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (completed != null) 'completed': completed,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PlaybackProgressesCompanion copyWith({
    Value<int>? id,
    Value<String>? targetType,
    Value<int>? targetId,
    Value<int?>? workId,
    Value<int?>? episodeId,
    Value<int?>? lastFileId,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<bool>? completed,
    Value<DateTime>? updatedAt,
  }) {
    return PlaybackProgressesCompanion(
      id: id ?? this.id,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      workId: workId ?? this.workId,
      episodeId: episodeId ?? this.episodeId,
      lastFileId: lastFileId ?? this.lastFileId,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      completed: completed ?? this.completed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (targetType.present) {
      map['target_type'] = Variable<String>(targetType.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<int>(targetId.value);
    }
    if (workId.present) {
      map['work_id'] = Variable<int>(workId.value);
    }
    if (episodeId.present) {
      map['episode_id'] = Variable<int>(episodeId.value);
    }
    if (lastFileId.present) {
      map['last_file_id'] = Variable<int>(lastFileId.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackProgressesCompanion(')
          ..write('id: $id, ')
          ..write('targetType: $targetType, ')
          ..write('targetId: $targetId, ')
          ..write('workId: $workId, ')
          ..write('episodeId: $episodeId, ')
          ..write('lastFileId: $lastFileId, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('completed: $completed, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ExternalIdsTable extends ExternalIds
    with TableInfo<$ExternalIdsTable, ExternalIdData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExternalIdsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<int> workId = GeneratedColumn<int>(
    'work_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES works (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerEntityIdMeta = const VerificationMeta(
    'providerEntityId',
  );
  @override
  late final GeneratedColumn<String> providerEntityId = GeneratedColumn<String>(
    'provider_entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workId,
    provider,
    providerEntityId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'external_ids';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExternalIdData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workIdMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('provider_entity_id')) {
      context.handle(
        _providerEntityIdMeta,
        providerEntityId.isAcceptableOrUnknown(
          data['provider_entity_id']!,
          _providerEntityIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_providerEntityIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {provider, providerEntityId},
  ];
  @override
  ExternalIdData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExternalIdData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}work_id'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      providerEntityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider_entity_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ExternalIdsTable createAlias(String alias) {
    return $ExternalIdsTable(attachedDatabase, alias);
  }
}

class ExternalIdData extends DataClass implements Insertable<ExternalIdData> {
  final int id;
  final int workId;
  final String provider;
  final String providerEntityId;
  final DateTime createdAt;
  const ExternalIdData({
    required this.id,
    required this.workId,
    required this.provider,
    required this.providerEntityId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['work_id'] = Variable<int>(workId);
    map['provider'] = Variable<String>(provider);
    map['provider_entity_id'] = Variable<String>(providerEntityId);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ExternalIdsCompanion toCompanion(bool nullToAbsent) {
    return ExternalIdsCompanion(
      id: Value(id),
      workId: Value(workId),
      provider: Value(provider),
      providerEntityId: Value(providerEntityId),
      createdAt: Value(createdAt),
    );
  }

  factory ExternalIdData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExternalIdData(
      id: serializer.fromJson<int>(json['id']),
      workId: serializer.fromJson<int>(json['workId']),
      provider: serializer.fromJson<String>(json['provider']),
      providerEntityId: serializer.fromJson<String>(json['providerEntityId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'workId': serializer.toJson<int>(workId),
      'provider': serializer.toJson<String>(provider),
      'providerEntityId': serializer.toJson<String>(providerEntityId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ExternalIdData copyWith({
    int? id,
    int? workId,
    String? provider,
    String? providerEntityId,
    DateTime? createdAt,
  }) => ExternalIdData(
    id: id ?? this.id,
    workId: workId ?? this.workId,
    provider: provider ?? this.provider,
    providerEntityId: providerEntityId ?? this.providerEntityId,
    createdAt: createdAt ?? this.createdAt,
  );
  ExternalIdData copyWithCompanion(ExternalIdsCompanion data) {
    return ExternalIdData(
      id: data.id.present ? data.id.value : this.id,
      workId: data.workId.present ? data.workId.value : this.workId,
      provider: data.provider.present ? data.provider.value : this.provider,
      providerEntityId: data.providerEntityId.present
          ? data.providerEntityId.value
          : this.providerEntityId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExternalIdData(')
          ..write('id: $id, ')
          ..write('workId: $workId, ')
          ..write('provider: $provider, ')
          ..write('providerEntityId: $providerEntityId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, workId, provider, providerEntityId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExternalIdData &&
          other.id == this.id &&
          other.workId == this.workId &&
          other.provider == this.provider &&
          other.providerEntityId == this.providerEntityId &&
          other.createdAt == this.createdAt);
}

class ExternalIdsCompanion extends UpdateCompanion<ExternalIdData> {
  final Value<int> id;
  final Value<int> workId;
  final Value<String> provider;
  final Value<String> providerEntityId;
  final Value<DateTime> createdAt;
  const ExternalIdsCompanion({
    this.id = const Value.absent(),
    this.workId = const Value.absent(),
    this.provider = const Value.absent(),
    this.providerEntityId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ExternalIdsCompanion.insert({
    this.id = const Value.absent(),
    required int workId,
    required String provider,
    required String providerEntityId,
    this.createdAt = const Value.absent(),
  }) : workId = Value(workId),
       provider = Value(provider),
       providerEntityId = Value(providerEntityId);
  static Insertable<ExternalIdData> custom({
    Expression<int>? id,
    Expression<int>? workId,
    Expression<String>? provider,
    Expression<String>? providerEntityId,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workId != null) 'work_id': workId,
      if (provider != null) 'provider': provider,
      if (providerEntityId != null) 'provider_entity_id': providerEntityId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ExternalIdsCompanion copyWith({
    Value<int>? id,
    Value<int>? workId,
    Value<String>? provider,
    Value<String>? providerEntityId,
    Value<DateTime>? createdAt,
  }) {
    return ExternalIdsCompanion(
      id: id ?? this.id,
      workId: workId ?? this.workId,
      provider: provider ?? this.provider,
      providerEntityId: providerEntityId ?? this.providerEntityId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (workId.present) {
      map['work_id'] = Variable<int>(workId.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (providerEntityId.present) {
      map['provider_entity_id'] = Variable<String>(providerEntityId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExternalIdsCompanion(')
          ..write('id: $id, ')
          ..write('workId: $workId, ')
          ..write('provider: $provider, ')
          ..write('providerEntityId: $providerEntityId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $MetadataCachesTable extends MetadataCaches
    with TableInfo<$MetadataCachesTable, MetadataCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetadataCachesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    cacheKey,
    provider,
    payloadJson,
    etag,
    expiresAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'metadata_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetadataCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  MetadataCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetadataCacheData(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MetadataCachesTable createAlias(String alias) {
    return $MetadataCachesTable(attachedDatabase, alias);
  }
}

class MetadataCacheData extends DataClass
    implements Insertable<MetadataCacheData> {
  final String cacheKey;
  final String provider;
  final String payloadJson;
  final String? etag;
  final DateTime expiresAt;
  final DateTime updatedAt;
  const MetadataCacheData({
    required this.cacheKey,
    required this.provider,
    required this.payloadJson,
    this.etag,
    required this.expiresAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['provider'] = Variable<String>(provider);
    map['payload_json'] = Variable<String>(payloadJson);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    map['expires_at'] = Variable<DateTime>(expiresAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MetadataCachesCompanion toCompanion(bool nullToAbsent) {
    return MetadataCachesCompanion(
      cacheKey: Value(cacheKey),
      provider: Value(provider),
      payloadJson: Value(payloadJson),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      expiresAt: Value(expiresAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MetadataCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetadataCacheData(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      provider: serializer.fromJson<String>(json['provider']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      etag: serializer.fromJson<String?>(json['etag']),
      expiresAt: serializer.fromJson<DateTime>(json['expiresAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'provider': serializer.toJson<String>(provider),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'etag': serializer.toJson<String?>(etag),
      'expiresAt': serializer.toJson<DateTime>(expiresAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MetadataCacheData copyWith({
    String? cacheKey,
    String? provider,
    String? payloadJson,
    Value<String?> etag = const Value.absent(),
    DateTime? expiresAt,
    DateTime? updatedAt,
  }) => MetadataCacheData(
    cacheKey: cacheKey ?? this.cacheKey,
    provider: provider ?? this.provider,
    payloadJson: payloadJson ?? this.payloadJson,
    etag: etag.present ? etag.value : this.etag,
    expiresAt: expiresAt ?? this.expiresAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MetadataCacheData copyWithCompanion(MetadataCachesCompanion data) {
    return MetadataCacheData(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      provider: data.provider.present ? data.provider.value : this.provider,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      etag: data.etag.present ? data.etag.value : this.etag,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetadataCacheData(')
          ..write('cacheKey: $cacheKey, ')
          ..write('provider: $provider, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('etag: $etag, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(cacheKey, provider, payloadJson, etag, expiresAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetadataCacheData &&
          other.cacheKey == this.cacheKey &&
          other.provider == this.provider &&
          other.payloadJson == this.payloadJson &&
          other.etag == this.etag &&
          other.expiresAt == this.expiresAt &&
          other.updatedAt == this.updatedAt);
}

class MetadataCachesCompanion extends UpdateCompanion<MetadataCacheData> {
  final Value<String> cacheKey;
  final Value<String> provider;
  final Value<String> payloadJson;
  final Value<String?> etag;
  final Value<DateTime> expiresAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MetadataCachesCompanion({
    this.cacheKey = const Value.absent(),
    this.provider = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.etag = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetadataCachesCompanion.insert({
    required String cacheKey,
    required String provider,
    required String payloadJson,
    this.etag = const Value.absent(),
    required DateTime expiresAt,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       provider = Value(provider),
       payloadJson = Value(payloadJson),
       expiresAt = Value(expiresAt);
  static Insertable<MetadataCacheData> custom({
    Expression<String>? cacheKey,
    Expression<String>? provider,
    Expression<String>? payloadJson,
    Expression<String>? etag,
    Expression<DateTime>? expiresAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (provider != null) 'provider': provider,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (etag != null) 'etag': etag,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetadataCachesCompanion copyWith({
    Value<String>? cacheKey,
    Value<String>? provider,
    Value<String>? payloadJson,
    Value<String?>? etag,
    Value<DateTime>? expiresAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MetadataCachesCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      provider: provider ?? this.provider,
      payloadJson: payloadJson ?? this.payloadJson,
      etag: etag ?? this.etag,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetadataCachesCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('provider: $provider, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('etag: $etag, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final String key;
  final String value;
  const SyncStateData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(key: Value(key), value: Value(value));
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncStateData copyWith({String? key, String? value}) =>
      SyncStateData(key: key ?? this.key, value: value ?? this.value);
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncStateData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorsTable extends SyncCursors
    with TableInfo<$SyncCursorsTable, SyncCursorData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSequenceMeta = const VerificationMeta(
    'lastSequence',
  );
  @override
  late final GeneratedColumn<int> lastSequence = GeneratedColumn<int>(
    'last_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [deviceId, lastSequence, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursorData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('last_sequence')) {
      context.handle(
        _lastSequenceMeta,
        lastSequence.isAcceptableOrUnknown(
          data['last_sequence']!,
          _lastSequenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSequenceMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  SyncCursorData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursorData(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      lastSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_sequence'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }
}

class SyncCursorData extends DataClass implements Insertable<SyncCursorData> {
  final String deviceId;
  final int lastSequence;
  final int updatedAt;
  const SyncCursorData({
    required this.deviceId,
    required this.lastSequence,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['last_sequence'] = Variable<int>(lastSequence);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(
      deviceId: Value(deviceId),
      lastSequence: Value(lastSequence),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncCursorData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursorData(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      lastSequence: serializer.fromJson<int>(json['lastSequence']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'lastSequence': serializer.toJson<int>(lastSequence),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SyncCursorData copyWith({
    String? deviceId,
    int? lastSequence,
    int? updatedAt,
  }) => SyncCursorData(
    deviceId: deviceId ?? this.deviceId,
    lastSequence: lastSequence ?? this.lastSequence,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncCursorData copyWithCompanion(SyncCursorsCompanion data) {
    return SyncCursorData(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      lastSequence: data.lastSequence.present
          ? data.lastSequence.value
          : this.lastSequence,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorData(')
          ..write('deviceId: $deviceId, ')
          ..write('lastSequence: $lastSequence, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(deviceId, lastSequence, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursorData &&
          other.deviceId == this.deviceId &&
          other.lastSequence == this.lastSequence &&
          other.updatedAt == this.updatedAt);
}

class SyncCursorsCompanion extends UpdateCompanion<SyncCursorData> {
  final Value<String> deviceId;
  final Value<int> lastSequence;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SyncCursorsCompanion({
    this.deviceId = const Value.absent(),
    this.lastSequence = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    required String deviceId,
    required int lastSequence,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       lastSequence = Value(lastSequence),
       updatedAt = Value(updatedAt);
  static Insertable<SyncCursorData> custom({
    Expression<String>? deviceId,
    Expression<int>? lastSequence,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (lastSequence != null) 'last_sequence': lastSequence,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorsCompanion copyWith({
    Value<String>? deviceId,
    Value<int>? lastSequence,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncCursorsCompanion(
      deviceId: deviceId ?? this.deviceId,
      lastSequence: lastSequence ?? this.lastSequence,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (lastSequence.present) {
      map['last_sequence'] = Variable<int>(lastSequence.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('lastSequence: $lastSequence, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncLocalRegistersTable extends SyncLocalRegisters
    with TableInfo<$SyncLocalRegistersTable, SyncLocalRegisterData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncLocalRegistersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordKeyMeta = const VerificationMeta(
    'recordKey',
  );
  @override
  late final GeneratedColumn<String> recordKey = GeneratedColumn<String>(
    'record_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetJsonMeta = const VerificationMeta(
    'targetJson',
  );
  @override
  late final GeneratedColumn<String> targetJson = GeneratedColumn<String>(
    'target_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionStampMeta = const VerificationMeta(
    'versionStamp',
  );
  @override
  late final GeneratedColumn<int> versionStamp = GeneratedColumn<int>(
    'version_stamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionDeviceIdMeta = const VerificationMeta(
    'versionDeviceId',
  );
  @override
  late final GeneratedColumn<String> versionDeviceId = GeneratedColumn<String>(
    'version_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    recordKey,
    kind,
    targetId,
    targetJson,
    versionStamp,
    versionDeviceId,
    valueJson,
    dirty,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_local_registers';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncLocalRegisterData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('record_key')) {
      context.handle(
        _recordKeyMeta,
        recordKey.isAcceptableOrUnknown(data['record_key']!, _recordKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_recordKeyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('target_json')) {
      context.handle(
        _targetJsonMeta,
        targetJson.isAcceptableOrUnknown(data['target_json']!, _targetJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_targetJsonMeta);
    }
    if (data.containsKey('version_stamp')) {
      context.handle(
        _versionStampMeta,
        versionStamp.isAcceptableOrUnknown(
          data['version_stamp']!,
          _versionStampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionStampMeta);
    }
    if (data.containsKey('version_device_id')) {
      context.handle(
        _versionDeviceIdMeta,
        versionDeviceId.isAcceptableOrUnknown(
          data['version_device_id']!,
          _versionDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionDeviceIdMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordKey};
  @override
  SyncLocalRegisterData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncLocalRegisterData(
      recordKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_key'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      targetJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_json'],
      )!,
      versionStamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version_stamp'],
      )!,
      versionDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_device_id'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncLocalRegistersTable createAlias(String alias) {
    return $SyncLocalRegistersTable(attachedDatabase, alias);
  }
}

class SyncLocalRegisterData extends DataClass
    implements Insertable<SyncLocalRegisterData> {
  final String recordKey;
  final String kind;
  final String targetId;
  final String targetJson;
  final int versionStamp;
  final String versionDeviceId;
  final String valueJson;
  final bool dirty;
  final int updatedAt;
  const SyncLocalRegisterData({
    required this.recordKey,
    required this.kind,
    required this.targetId,
    required this.targetJson,
    required this.versionStamp,
    required this.versionDeviceId,
    required this.valueJson,
    required this.dirty,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['record_key'] = Variable<String>(recordKey);
    map['kind'] = Variable<String>(kind);
    map['target_id'] = Variable<String>(targetId);
    map['target_json'] = Variable<String>(targetJson);
    map['version_stamp'] = Variable<int>(versionStamp);
    map['version_device_id'] = Variable<String>(versionDeviceId);
    map['value_json'] = Variable<String>(valueJson);
    map['dirty'] = Variable<bool>(dirty);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SyncLocalRegistersCompanion toCompanion(bool nullToAbsent) {
    return SyncLocalRegistersCompanion(
      recordKey: Value(recordKey),
      kind: Value(kind),
      targetId: Value(targetId),
      targetJson: Value(targetJson),
      versionStamp: Value(versionStamp),
      versionDeviceId: Value(versionDeviceId),
      valueJson: Value(valueJson),
      dirty: Value(dirty),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncLocalRegisterData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncLocalRegisterData(
      recordKey: serializer.fromJson<String>(json['recordKey']),
      kind: serializer.fromJson<String>(json['kind']),
      targetId: serializer.fromJson<String>(json['targetId']),
      targetJson: serializer.fromJson<String>(json['targetJson']),
      versionStamp: serializer.fromJson<int>(json['versionStamp']),
      versionDeviceId: serializer.fromJson<String>(json['versionDeviceId']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
      dirty: serializer.fromJson<bool>(json['dirty']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordKey': serializer.toJson<String>(recordKey),
      'kind': serializer.toJson<String>(kind),
      'targetId': serializer.toJson<String>(targetId),
      'targetJson': serializer.toJson<String>(targetJson),
      'versionStamp': serializer.toJson<int>(versionStamp),
      'versionDeviceId': serializer.toJson<String>(versionDeviceId),
      'valueJson': serializer.toJson<String>(valueJson),
      'dirty': serializer.toJson<bool>(dirty),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SyncLocalRegisterData copyWith({
    String? recordKey,
    String? kind,
    String? targetId,
    String? targetJson,
    int? versionStamp,
    String? versionDeviceId,
    String? valueJson,
    bool? dirty,
    int? updatedAt,
  }) => SyncLocalRegisterData(
    recordKey: recordKey ?? this.recordKey,
    kind: kind ?? this.kind,
    targetId: targetId ?? this.targetId,
    targetJson: targetJson ?? this.targetJson,
    versionStamp: versionStamp ?? this.versionStamp,
    versionDeviceId: versionDeviceId ?? this.versionDeviceId,
    valueJson: valueJson ?? this.valueJson,
    dirty: dirty ?? this.dirty,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncLocalRegisterData copyWithCompanion(SyncLocalRegistersCompanion data) {
    return SyncLocalRegisterData(
      recordKey: data.recordKey.present ? data.recordKey.value : this.recordKey,
      kind: data.kind.present ? data.kind.value : this.kind,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      targetJson: data.targetJson.present
          ? data.targetJson.value
          : this.targetJson,
      versionStamp: data.versionStamp.present
          ? data.versionStamp.value
          : this.versionStamp,
      versionDeviceId: data.versionDeviceId.present
          ? data.versionDeviceId.value
          : this.versionDeviceId,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncLocalRegisterData(')
          ..write('recordKey: $recordKey, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('targetJson: $targetJson, ')
          ..write('versionStamp: $versionStamp, ')
          ..write('versionDeviceId: $versionDeviceId, ')
          ..write('valueJson: $valueJson, ')
          ..write('dirty: $dirty, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    recordKey,
    kind,
    targetId,
    targetJson,
    versionStamp,
    versionDeviceId,
    valueJson,
    dirty,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncLocalRegisterData &&
          other.recordKey == this.recordKey &&
          other.kind == this.kind &&
          other.targetId == this.targetId &&
          other.targetJson == this.targetJson &&
          other.versionStamp == this.versionStamp &&
          other.versionDeviceId == this.versionDeviceId &&
          other.valueJson == this.valueJson &&
          other.dirty == this.dirty &&
          other.updatedAt == this.updatedAt);
}

class SyncLocalRegistersCompanion
    extends UpdateCompanion<SyncLocalRegisterData> {
  final Value<String> recordKey;
  final Value<String> kind;
  final Value<String> targetId;
  final Value<String> targetJson;
  final Value<int> versionStamp;
  final Value<String> versionDeviceId;
  final Value<String> valueJson;
  final Value<bool> dirty;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SyncLocalRegistersCompanion({
    this.recordKey = const Value.absent(),
    this.kind = const Value.absent(),
    this.targetId = const Value.absent(),
    this.targetJson = const Value.absent(),
    this.versionStamp = const Value.absent(),
    this.versionDeviceId = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.dirty = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncLocalRegistersCompanion.insert({
    required String recordKey,
    required String kind,
    required String targetId,
    required String targetJson,
    required int versionStamp,
    required String versionDeviceId,
    required String valueJson,
    this.dirty = const Value.absent(),
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : recordKey = Value(recordKey),
       kind = Value(kind),
       targetId = Value(targetId),
       targetJson = Value(targetJson),
       versionStamp = Value(versionStamp),
       versionDeviceId = Value(versionDeviceId),
       valueJson = Value(valueJson),
       updatedAt = Value(updatedAt);
  static Insertable<SyncLocalRegisterData> custom({
    Expression<String>? recordKey,
    Expression<String>? kind,
    Expression<String>? targetId,
    Expression<String>? targetJson,
    Expression<int>? versionStamp,
    Expression<String>? versionDeviceId,
    Expression<String>? valueJson,
    Expression<bool>? dirty,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordKey != null) 'record_key': recordKey,
      if (kind != null) 'kind': kind,
      if (targetId != null) 'target_id': targetId,
      if (targetJson != null) 'target_json': targetJson,
      if (versionStamp != null) 'version_stamp': versionStamp,
      if (versionDeviceId != null) 'version_device_id': versionDeviceId,
      if (valueJson != null) 'value_json': valueJson,
      if (dirty != null) 'dirty': dirty,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncLocalRegistersCompanion copyWith({
    Value<String>? recordKey,
    Value<String>? kind,
    Value<String>? targetId,
    Value<String>? targetJson,
    Value<int>? versionStamp,
    Value<String>? versionDeviceId,
    Value<String>? valueJson,
    Value<bool>? dirty,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncLocalRegistersCompanion(
      recordKey: recordKey ?? this.recordKey,
      kind: kind ?? this.kind,
      targetId: targetId ?? this.targetId,
      targetJson: targetJson ?? this.targetJson,
      versionStamp: versionStamp ?? this.versionStamp,
      versionDeviceId: versionDeviceId ?? this.versionDeviceId,
      valueJson: valueJson ?? this.valueJson,
      dirty: dirty ?? this.dirty,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordKey.present) {
      map['record_key'] = Variable<String>(recordKey.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (targetJson.present) {
      map['target_json'] = Variable<String>(targetJson.value);
    }
    if (versionStamp.present) {
      map['version_stamp'] = Variable<int>(versionStamp.value);
    }
    if (versionDeviceId.present) {
      map['version_device_id'] = Variable<String>(versionDeviceId.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncLocalRegistersCompanion(')
          ..write('recordKey: $recordKey, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('targetJson: $targetJson, ')
          ..write('versionStamp: $versionStamp, ')
          ..write('versionDeviceId: $versionDeviceId, ')
          ..write('valueJson: $valueJson, ')
          ..write('dirty: $dirty, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordKeyMeta = const VerificationMeta(
    'recordKey',
  );
  @override
  late final GeneratedColumn<String> recordKey = GeneratedColumn<String>(
    'record_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetJsonMeta = const VerificationMeta(
    'targetJson',
  );
  @override
  late final GeneratedColumn<String> targetJson = GeneratedColumn<String>(
    'target_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionStampMeta = const VerificationMeta(
    'versionStamp',
  );
  @override
  late final GeneratedColumn<int> versionStamp = GeneratedColumn<int>(
    'version_stamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionDeviceIdMeta = const VerificationMeta(
    'versionDeviceId',
  );
  @override
  late final GeneratedColumn<String> versionDeviceId = GeneratedColumn<String>(
    'version_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sequence,
    recordKey,
    kind,
    targetJson,
    versionStamp,
    versionDeviceId,
    valueJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('record_key')) {
      context.handle(
        _recordKeyMeta,
        recordKey.isAcceptableOrUnknown(data['record_key']!, _recordKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_recordKeyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('target_json')) {
      context.handle(
        _targetJsonMeta,
        targetJson.isAcceptableOrUnknown(data['target_json']!, _targetJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_targetJsonMeta);
    }
    if (data.containsKey('version_stamp')) {
      context.handle(
        _versionStampMeta,
        versionStamp.isAcceptableOrUnknown(
          data['version_stamp']!,
          _versionStampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionStampMeta);
    }
    if (data.containsKey('version_device_id')) {
      context.handle(
        _versionDeviceIdMeta,
        versionDeviceId.isAcceptableOrUnknown(
          data['version_device_id']!,
          _versionDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionDeviceIdMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sequence, recordKey};
  @override
  SyncOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxData(
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      recordKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_key'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      targetJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_json'],
      )!,
      versionStamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version_stamp'],
      )!,
      versionDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_device_id'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxData extends DataClass implements Insertable<SyncOutboxData> {
  final int sequence;
  final String recordKey;
  final String kind;
  final String targetJson;
  final int versionStamp;
  final String versionDeviceId;
  final String valueJson;
  final int createdAt;
  const SyncOutboxData({
    required this.sequence,
    required this.recordKey,
    required this.kind,
    required this.targetJson,
    required this.versionStamp,
    required this.versionDeviceId,
    required this.valueJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sequence'] = Variable<int>(sequence);
    map['record_key'] = Variable<String>(recordKey);
    map['kind'] = Variable<String>(kind);
    map['target_json'] = Variable<String>(targetJson);
    map['version_stamp'] = Variable<int>(versionStamp);
    map['version_device_id'] = Variable<String>(versionDeviceId);
    map['value_json'] = Variable<String>(valueJson);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      sequence: Value(sequence),
      recordKey: Value(recordKey),
      kind: Value(kind),
      targetJson: Value(targetJson),
      versionStamp: Value(versionStamp),
      versionDeviceId: Value(versionDeviceId),
      valueJson: Value(valueJson),
      createdAt: Value(createdAt),
    );
  }

  factory SyncOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxData(
      sequence: serializer.fromJson<int>(json['sequence']),
      recordKey: serializer.fromJson<String>(json['recordKey']),
      kind: serializer.fromJson<String>(json['kind']),
      targetJson: serializer.fromJson<String>(json['targetJson']),
      versionStamp: serializer.fromJson<int>(json['versionStamp']),
      versionDeviceId: serializer.fromJson<String>(json['versionDeviceId']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sequence': serializer.toJson<int>(sequence),
      'recordKey': serializer.toJson<String>(recordKey),
      'kind': serializer.toJson<String>(kind),
      'targetJson': serializer.toJson<String>(targetJson),
      'versionStamp': serializer.toJson<int>(versionStamp),
      'versionDeviceId': serializer.toJson<String>(versionDeviceId),
      'valueJson': serializer.toJson<String>(valueJson),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  SyncOutboxData copyWith({
    int? sequence,
    String? recordKey,
    String? kind,
    String? targetJson,
    int? versionStamp,
    String? versionDeviceId,
    String? valueJson,
    int? createdAt,
  }) => SyncOutboxData(
    sequence: sequence ?? this.sequence,
    recordKey: recordKey ?? this.recordKey,
    kind: kind ?? this.kind,
    targetJson: targetJson ?? this.targetJson,
    versionStamp: versionStamp ?? this.versionStamp,
    versionDeviceId: versionDeviceId ?? this.versionDeviceId,
    valueJson: valueJson ?? this.valueJson,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncOutboxData copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxData(
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      recordKey: data.recordKey.present ? data.recordKey.value : this.recordKey,
      kind: data.kind.present ? data.kind.value : this.kind,
      targetJson: data.targetJson.present
          ? data.targetJson.value
          : this.targetJson,
      versionStamp: data.versionStamp.present
          ? data.versionStamp.value
          : this.versionStamp,
      versionDeviceId: data.versionDeviceId.present
          ? data.versionDeviceId.value
          : this.versionDeviceId,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxData(')
          ..write('sequence: $sequence, ')
          ..write('recordKey: $recordKey, ')
          ..write('kind: $kind, ')
          ..write('targetJson: $targetJson, ')
          ..write('versionStamp: $versionStamp, ')
          ..write('versionDeviceId: $versionDeviceId, ')
          ..write('valueJson: $valueJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sequence,
    recordKey,
    kind,
    targetJson,
    versionStamp,
    versionDeviceId,
    valueJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxData &&
          other.sequence == this.sequence &&
          other.recordKey == this.recordKey &&
          other.kind == this.kind &&
          other.targetJson == this.targetJson &&
          other.versionStamp == this.versionStamp &&
          other.versionDeviceId == this.versionDeviceId &&
          other.valueJson == this.valueJson &&
          other.createdAt == this.createdAt);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxData> {
  final Value<int> sequence;
  final Value<String> recordKey;
  final Value<String> kind;
  final Value<String> targetJson;
  final Value<int> versionStamp;
  final Value<String> versionDeviceId;
  final Value<String> valueJson;
  final Value<int> createdAt;
  final Value<int> rowid;
  const SyncOutboxCompanion({
    this.sequence = const Value.absent(),
    this.recordKey = const Value.absent(),
    this.kind = const Value.absent(),
    this.targetJson = const Value.absent(),
    this.versionStamp = const Value.absent(),
    this.versionDeviceId = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    required int sequence,
    required String recordKey,
    required String kind,
    required String targetJson,
    required int versionStamp,
    required String versionDeviceId,
    required String valueJson,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : sequence = Value(sequence),
       recordKey = Value(recordKey),
       kind = Value(kind),
       targetJson = Value(targetJson),
       versionStamp = Value(versionStamp),
       versionDeviceId = Value(versionDeviceId),
       valueJson = Value(valueJson),
       createdAt = Value(createdAt);
  static Insertable<SyncOutboxData> custom({
    Expression<int>? sequence,
    Expression<String>? recordKey,
    Expression<String>? kind,
    Expression<String>? targetJson,
    Expression<int>? versionStamp,
    Expression<String>? versionDeviceId,
    Expression<String>? valueJson,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sequence != null) 'sequence': sequence,
      if (recordKey != null) 'record_key': recordKey,
      if (kind != null) 'kind': kind,
      if (targetJson != null) 'target_json': targetJson,
      if (versionStamp != null) 'version_stamp': versionStamp,
      if (versionDeviceId != null) 'version_device_id': versionDeviceId,
      if (valueJson != null) 'value_json': valueJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<int>? sequence,
    Value<String>? recordKey,
    Value<String>? kind,
    Value<String>? targetJson,
    Value<int>? versionStamp,
    Value<String>? versionDeviceId,
    Value<String>? valueJson,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return SyncOutboxCompanion(
      sequence: sequence ?? this.sequence,
      recordKey: recordKey ?? this.recordKey,
      kind: kind ?? this.kind,
      targetJson: targetJson ?? this.targetJson,
      versionStamp: versionStamp ?? this.versionStamp,
      versionDeviceId: versionDeviceId ?? this.versionDeviceId,
      valueJson: valueJson ?? this.valueJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (recordKey.present) {
      map['record_key'] = Variable<String>(recordKey.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (targetJson.present) {
      map['target_json'] = Variable<String>(targetJson.value);
    }
    if (versionStamp.present) {
      map['version_stamp'] = Variable<int>(versionStamp.value);
    }
    if (versionDeviceId.present) {
      map['version_device_id'] = Variable<String>(versionDeviceId.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('sequence: $sequence, ')
          ..write('recordKey: $recordKey, ')
          ..write('kind: $kind, ')
          ..write('targetJson: $targetJson, ')
          ..write('versionStamp: $versionStamp, ')
          ..write('versionDeviceId: $versionDeviceId, ')
          ..write('valueJson: $valueJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncPendingTable extends SyncPending
    with TableInfo<$SyncPendingTable, SyncPendingData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncPendingTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordKeyMeta = const VerificationMeta(
    'recordKey',
  );
  @override
  late final GeneratedColumn<String> recordKey = GeneratedColumn<String>(
    'record_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetJsonMeta = const VerificationMeta(
    'targetJson',
  );
  @override
  late final GeneratedColumn<String> targetJson = GeneratedColumn<String>(
    'target_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionStampMeta = const VerificationMeta(
    'versionStamp',
  );
  @override
  late final GeneratedColumn<int> versionStamp = GeneratedColumn<int>(
    'version_stamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionDeviceIdMeta = const VerificationMeta(
    'versionDeviceId',
  );
  @override
  late final GeneratedColumn<String> versionDeviceId = GeneratedColumn<String>(
    'version_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    recordKey,
    kind,
    targetId,
    targetJson,
    versionStamp,
    versionDeviceId,
    valueJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_pending';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncPendingData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('record_key')) {
      context.handle(
        _recordKeyMeta,
        recordKey.isAcceptableOrUnknown(data['record_key']!, _recordKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_recordKeyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('target_json')) {
      context.handle(
        _targetJsonMeta,
        targetJson.isAcceptableOrUnknown(data['target_json']!, _targetJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_targetJsonMeta);
    }
    if (data.containsKey('version_stamp')) {
      context.handle(
        _versionStampMeta,
        versionStamp.isAcceptableOrUnknown(
          data['version_stamp']!,
          _versionStampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionStampMeta);
    }
    if (data.containsKey('version_device_id')) {
      context.handle(
        _versionDeviceIdMeta,
        versionDeviceId.isAcceptableOrUnknown(
          data['version_device_id']!,
          _versionDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionDeviceIdMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordKey};
  @override
  SyncPendingData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncPendingData(
      recordKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_key'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      targetJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_json'],
      )!,
      versionStamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version_stamp'],
      )!,
      versionDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_device_id'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncPendingTable createAlias(String alias) {
    return $SyncPendingTable(attachedDatabase, alias);
  }
}

class SyncPendingData extends DataClass implements Insertable<SyncPendingData> {
  final String recordKey;
  final String kind;
  final String targetId;
  final String targetJson;
  final int versionStamp;
  final String versionDeviceId;
  final String valueJson;
  final int updatedAt;
  const SyncPendingData({
    required this.recordKey,
    required this.kind,
    required this.targetId,
    required this.targetJson,
    required this.versionStamp,
    required this.versionDeviceId,
    required this.valueJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['record_key'] = Variable<String>(recordKey);
    map['kind'] = Variable<String>(kind);
    map['target_id'] = Variable<String>(targetId);
    map['target_json'] = Variable<String>(targetJson);
    map['version_stamp'] = Variable<int>(versionStamp);
    map['version_device_id'] = Variable<String>(versionDeviceId);
    map['value_json'] = Variable<String>(valueJson);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SyncPendingCompanion toCompanion(bool nullToAbsent) {
    return SyncPendingCompanion(
      recordKey: Value(recordKey),
      kind: Value(kind),
      targetId: Value(targetId),
      targetJson: Value(targetJson),
      versionStamp: Value(versionStamp),
      versionDeviceId: Value(versionDeviceId),
      valueJson: Value(valueJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncPendingData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncPendingData(
      recordKey: serializer.fromJson<String>(json['recordKey']),
      kind: serializer.fromJson<String>(json['kind']),
      targetId: serializer.fromJson<String>(json['targetId']),
      targetJson: serializer.fromJson<String>(json['targetJson']),
      versionStamp: serializer.fromJson<int>(json['versionStamp']),
      versionDeviceId: serializer.fromJson<String>(json['versionDeviceId']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordKey': serializer.toJson<String>(recordKey),
      'kind': serializer.toJson<String>(kind),
      'targetId': serializer.toJson<String>(targetId),
      'targetJson': serializer.toJson<String>(targetJson),
      'versionStamp': serializer.toJson<int>(versionStamp),
      'versionDeviceId': serializer.toJson<String>(versionDeviceId),
      'valueJson': serializer.toJson<String>(valueJson),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SyncPendingData copyWith({
    String? recordKey,
    String? kind,
    String? targetId,
    String? targetJson,
    int? versionStamp,
    String? versionDeviceId,
    String? valueJson,
    int? updatedAt,
  }) => SyncPendingData(
    recordKey: recordKey ?? this.recordKey,
    kind: kind ?? this.kind,
    targetId: targetId ?? this.targetId,
    targetJson: targetJson ?? this.targetJson,
    versionStamp: versionStamp ?? this.versionStamp,
    versionDeviceId: versionDeviceId ?? this.versionDeviceId,
    valueJson: valueJson ?? this.valueJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncPendingData copyWithCompanion(SyncPendingCompanion data) {
    return SyncPendingData(
      recordKey: data.recordKey.present ? data.recordKey.value : this.recordKey,
      kind: data.kind.present ? data.kind.value : this.kind,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      targetJson: data.targetJson.present
          ? data.targetJson.value
          : this.targetJson,
      versionStamp: data.versionStamp.present
          ? data.versionStamp.value
          : this.versionStamp,
      versionDeviceId: data.versionDeviceId.present
          ? data.versionDeviceId.value
          : this.versionDeviceId,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncPendingData(')
          ..write('recordKey: $recordKey, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('targetJson: $targetJson, ')
          ..write('versionStamp: $versionStamp, ')
          ..write('versionDeviceId: $versionDeviceId, ')
          ..write('valueJson: $valueJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    recordKey,
    kind,
    targetId,
    targetJson,
    versionStamp,
    versionDeviceId,
    valueJson,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPendingData &&
          other.recordKey == this.recordKey &&
          other.kind == this.kind &&
          other.targetId == this.targetId &&
          other.targetJson == this.targetJson &&
          other.versionStamp == this.versionStamp &&
          other.versionDeviceId == this.versionDeviceId &&
          other.valueJson == this.valueJson &&
          other.updatedAt == this.updatedAt);
}

class SyncPendingCompanion extends UpdateCompanion<SyncPendingData> {
  final Value<String> recordKey;
  final Value<String> kind;
  final Value<String> targetId;
  final Value<String> targetJson;
  final Value<int> versionStamp;
  final Value<String> versionDeviceId;
  final Value<String> valueJson;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SyncPendingCompanion({
    this.recordKey = const Value.absent(),
    this.kind = const Value.absent(),
    this.targetId = const Value.absent(),
    this.targetJson = const Value.absent(),
    this.versionStamp = const Value.absent(),
    this.versionDeviceId = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncPendingCompanion.insert({
    required String recordKey,
    required String kind,
    required String targetId,
    required String targetJson,
    required int versionStamp,
    required String versionDeviceId,
    required String valueJson,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : recordKey = Value(recordKey),
       kind = Value(kind),
       targetId = Value(targetId),
       targetJson = Value(targetJson),
       versionStamp = Value(versionStamp),
       versionDeviceId = Value(versionDeviceId),
       valueJson = Value(valueJson),
       updatedAt = Value(updatedAt);
  static Insertable<SyncPendingData> custom({
    Expression<String>? recordKey,
    Expression<String>? kind,
    Expression<String>? targetId,
    Expression<String>? targetJson,
    Expression<int>? versionStamp,
    Expression<String>? versionDeviceId,
    Expression<String>? valueJson,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordKey != null) 'record_key': recordKey,
      if (kind != null) 'kind': kind,
      if (targetId != null) 'target_id': targetId,
      if (targetJson != null) 'target_json': targetJson,
      if (versionStamp != null) 'version_stamp': versionStamp,
      if (versionDeviceId != null) 'version_device_id': versionDeviceId,
      if (valueJson != null) 'value_json': valueJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncPendingCompanion copyWith({
    Value<String>? recordKey,
    Value<String>? kind,
    Value<String>? targetId,
    Value<String>? targetJson,
    Value<int>? versionStamp,
    Value<String>? versionDeviceId,
    Value<String>? valueJson,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncPendingCompanion(
      recordKey: recordKey ?? this.recordKey,
      kind: kind ?? this.kind,
      targetId: targetId ?? this.targetId,
      targetJson: targetJson ?? this.targetJson,
      versionStamp: versionStamp ?? this.versionStamp,
      versionDeviceId: versionDeviceId ?? this.versionDeviceId,
      valueJson: valueJson ?? this.valueJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordKey.present) {
      map['record_key'] = Variable<String>(recordKey.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (targetJson.present) {
      map['target_json'] = Variable<String>(targetJson.value);
    }
    if (versionStamp.present) {
      map['version_stamp'] = Variable<int>(versionStamp.value);
    }
    if (versionDeviceId.present) {
      map['version_device_id'] = Variable<String>(versionDeviceId.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncPendingCompanion(')
          ..write('recordKey: $recordKey, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('targetJson: $targetJson, ')
          ..write('versionStamp: $versionStamp, ')
          ..write('versionDeviceId: $versionDeviceId, ')
          ..write('valueJson: $valueJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MediaSourcesTable mediaSources = $MediaSourcesTable(this);
  late final $MediaEntriesTable mediaEntries = $MediaEntriesTable(this);
  late final $MediaFilesTable mediaFiles = $MediaFilesTable(this);
  late final $WorksTable works = $WorksTable(this);
  late final $SeasonsTable seasons = $SeasonsTable(this);
  late final $EpisodesTable episodes = $EpisodesTable(this);
  late final $MediaAssignmentsTable mediaAssignments = $MediaAssignmentsTable(
    this,
  );
  late final $PlaybackProgressesTable playbackProgresses =
      $PlaybackProgressesTable(this);
  late final $ExternalIdsTable externalIds = $ExternalIdsTable(this);
  late final $MetadataCachesTable metadataCaches = $MetadataCachesTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $SyncCursorsTable syncCursors = $SyncCursorsTable(this);
  late final $SyncLocalRegistersTable syncLocalRegisters =
      $SyncLocalRegistersTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $SyncPendingTable syncPending = $SyncPendingTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    mediaSources,
    mediaEntries,
    mediaFiles,
    works,
    seasons,
    episodes,
    mediaAssignments,
    playbackProgresses,
    externalIds,
    metadataCaches,
    syncState,
    syncCursors,
    syncLocalRegisters,
    syncOutbox,
    syncPending,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media_sources',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('media_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media_entries',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('media_files', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'works',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('seasons', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'seasons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('episodes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media_files',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('media_assignments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'works',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('media_assignments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'episodes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('media_assignments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'works',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('playback_progress', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'episodes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('playback_progress', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media_files',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('playback_progress', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'works',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('external_ids', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$MediaSourcesTableCreateCompanionBuilder =
    MediaSourcesCompanion Function({
      Value<int> id,
      required String kind,
      required String name,
      required String rootLocator,
      Value<String?> credentialRef,
      Value<bool> enabled,
      Value<String> extensions,
      Value<String> excludedDirectories,
      Value<int> scanRevision,
      Value<DateTime?> lastScanAt,
      Value<String?> errorMessage,
    });
typedef $$MediaSourcesTableUpdateCompanionBuilder =
    MediaSourcesCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<String> name,
      Value<String> rootLocator,
      Value<String?> credentialRef,
      Value<bool> enabled,
      Value<String> extensions,
      Value<String> excludedDirectories,
      Value<int> scanRevision,
      Value<DateTime?> lastScanAt,
      Value<String?> errorMessage,
    });

final class $$MediaSourcesTableReferences
    extends
        BaseReferences<_$AppDatabase, $MediaSourcesTable, MediaSourceEntry> {
  $$MediaSourcesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MediaEntriesTable, List<MediaEntryData>>
  _mediaEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mediaEntries,
    aliasName: 'media_sources__id__media_entries__source_id',
  );

  $$MediaEntriesTableProcessedTableManager get mediaEntriesRefs {
    final manager = $$MediaEntriesTableTableManager(
      $_db,
      $_db.mediaEntries,
    ).filter((f) => f.sourceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_mediaEntriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MediaSourcesTableFilterComposer
    extends Composer<_$AppDatabase, $MediaSourcesTable> {
  $$MediaSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootLocator => $composableBuilder(
    column: $table.rootLocator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get credentialRef => $composableBuilder(
    column: $table.credentialRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get excludedDirectories => $composableBuilder(
    column: $table.excludedDirectories,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scanRevision => $composableBuilder(
    column: $table.scanRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> mediaEntriesRefs(
    Expression<bool> Function($$MediaEntriesTableFilterComposer f) f,
  ) {
    final $$MediaEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaEntries,
      getReferencedColumn: (t) => t.sourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaEntriesTableFilterComposer(
            $db: $db,
            $table: $db.mediaEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MediaSourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaSourcesTable> {
  $$MediaSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootLocator => $composableBuilder(
    column: $table.rootLocator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get credentialRef => $composableBuilder(
    column: $table.credentialRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get excludedDirectories => $composableBuilder(
    column: $table.excludedDirectories,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scanRevision => $composableBuilder(
    column: $table.scanRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaSourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaSourcesTable> {
  $$MediaSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get rootLocator => $composableBuilder(
    column: $table.rootLocator,
    builder: (column) => column,
  );

  GeneratedColumn<String> get credentialRef => $composableBuilder(
    column: $table.credentialRef,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get excludedDirectories => $composableBuilder(
    column: $table.excludedDirectories,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scanRevision => $composableBuilder(
    column: $table.scanRevision,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  Expression<T> mediaEntriesRefs<T extends Object>(
    Expression<T> Function($$MediaEntriesTableAnnotationComposer a) f,
  ) {
    final $$MediaEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaEntries,
      getReferencedColumn: (t) => t.sourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MediaSourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaSourcesTable,
          MediaSourceEntry,
          $$MediaSourcesTableFilterComposer,
          $$MediaSourcesTableOrderingComposer,
          $$MediaSourcesTableAnnotationComposer,
          $$MediaSourcesTableCreateCompanionBuilder,
          $$MediaSourcesTableUpdateCompanionBuilder,
          (MediaSourceEntry, $$MediaSourcesTableReferences),
          MediaSourceEntry,
          PrefetchHooks Function({bool mediaEntriesRefs})
        > {
  $$MediaSourcesTableTableManager(_$AppDatabase db, $MediaSourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaSourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> rootLocator = const Value.absent(),
                Value<String?> credentialRef = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> extensions = const Value.absent(),
                Value<String> excludedDirectories = const Value.absent(),
                Value<int> scanRevision = const Value.absent(),
                Value<DateTime?> lastScanAt = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
              }) => MediaSourcesCompanion(
                id: id,
                kind: kind,
                name: name,
                rootLocator: rootLocator,
                credentialRef: credentialRef,
                enabled: enabled,
                extensions: extensions,
                excludedDirectories: excludedDirectories,
                scanRevision: scanRevision,
                lastScanAt: lastScanAt,
                errorMessage: errorMessage,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                required String name,
                required String rootLocator,
                Value<String?> credentialRef = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> extensions = const Value.absent(),
                Value<String> excludedDirectories = const Value.absent(),
                Value<int> scanRevision = const Value.absent(),
                Value<DateTime?> lastScanAt = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
              }) => MediaSourcesCompanion.insert(
                id: id,
                kind: kind,
                name: name,
                rootLocator: rootLocator,
                credentialRef: credentialRef,
                enabled: enabled,
                extensions: extensions,
                excludedDirectories: excludedDirectories,
                scanRevision: scanRevision,
                lastScanAt: lastScanAt,
                errorMessage: errorMessage,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaSourcesTable, MediaSourceEntry>(table),
                  $$MediaSourcesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({mediaEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (mediaEntriesRefs) db.mediaEntries],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (mediaEntriesRefs)
                    await $_getPrefetchedData<
                      MediaSourceEntry,
                      $MediaSourcesTable,
                      MediaEntryData
                    >(
                      currentTable: table,
                      referencedTable: $$MediaSourcesTableReferences
                          ._mediaEntriesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$MediaSourcesTableReferences(
                            db,
                            table,
                            p0,
                          ).mediaEntriesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.sourceId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$MediaSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaSourcesTable,
      MediaSourceEntry,
      $$MediaSourcesTableFilterComposer,
      $$MediaSourcesTableOrderingComposer,
      $$MediaSourcesTableAnnotationComposer,
      $$MediaSourcesTableCreateCompanionBuilder,
      $$MediaSourcesTableUpdateCompanionBuilder,
      (MediaSourceEntry, $$MediaSourcesTableReferences),
      MediaSourceEntry,
      PrefetchHooks Function({bool mediaEntriesRefs})
    >;
typedef $$MediaEntriesTableCreateCompanionBuilder =
    MediaEntriesCompanion Function({
      Value<int> id,
      required int sourceId,
      required String externalEntryId,
      required String relativeLocator,
      required String name,
      required bool isDirectory,
      Value<int?> size,
      Value<int?> modifiedAt,
      Value<String?> etag,
      Value<bool> available,
      Value<int> lastSeenScanId,
    });
typedef $$MediaEntriesTableUpdateCompanionBuilder =
    MediaEntriesCompanion Function({
      Value<int> id,
      Value<int> sourceId,
      Value<String> externalEntryId,
      Value<String> relativeLocator,
      Value<String> name,
      Value<bool> isDirectory,
      Value<int?> size,
      Value<int?> modifiedAt,
      Value<String?> etag,
      Value<bool> available,
      Value<int> lastSeenScanId,
    });

final class $$MediaEntriesTableReferences
    extends BaseReferences<_$AppDatabase, $MediaEntriesTable, MediaEntryData> {
  $$MediaEntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MediaSourcesTable _sourceIdTable(_$AppDatabase db) => db.mediaSources
      .createAlias('media_entries__source_id__media_sources__id');

  $$MediaSourcesTableProcessedTableManager get sourceId {
    final $_column = $_itemColumn<int>('source_id')!;

    final manager = $$MediaSourcesTableTableManager(
      $_db,
      $_db.mediaSources,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$MediaFilesTable, List<MediaFileData>>
  _mediaFilesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mediaFiles,
    aliasName: 'media_entries__id__media_files__entry_id',
  );

  $$MediaFilesTableProcessedTableManager get mediaFilesRefs {
    final manager = $$MediaFilesTableTableManager(
      $_db,
      $_db.mediaFiles,
    ).filter((f) => f.entryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_mediaFilesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MediaEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $MediaEntriesTable> {
  $$MediaEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalEntryId => $composableBuilder(
    column: $table.externalEntryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativeLocator => $composableBuilder(
    column: $table.relativeLocator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDirectory => $composableBuilder(
    column: $table.isDirectory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get available => $composableBuilder(
    column: $table.available,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenScanId => $composableBuilder(
    column: $table.lastSeenScanId,
    builder: (column) => ColumnFilters(column),
  );

  $$MediaSourcesTableFilterComposer get sourceId {
    final $$MediaSourcesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.mediaSources,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaSourcesTableFilterComposer(
            $db: $db,
            $table: $db.mediaSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> mediaFilesRefs(
    Expression<bool> Function($$MediaFilesTableFilterComposer f) f,
  ) {
    final $$MediaFilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaFiles,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaFilesTableFilterComposer(
            $db: $db,
            $table: $db.mediaFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MediaEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaEntriesTable> {
  $$MediaEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalEntryId => $composableBuilder(
    column: $table.externalEntryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativeLocator => $composableBuilder(
    column: $table.relativeLocator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDirectory => $composableBuilder(
    column: $table.isDirectory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get available => $composableBuilder(
    column: $table.available,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenScanId => $composableBuilder(
    column: $table.lastSeenScanId,
    builder: (column) => ColumnOrderings(column),
  );

  $$MediaSourcesTableOrderingComposer get sourceId {
    final $$MediaSourcesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.mediaSources,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaSourcesTableOrderingComposer(
            $db: $db,
            $table: $db.mediaSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaEntriesTable> {
  $$MediaEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get externalEntryId => $composableBuilder(
    column: $table.externalEntryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get relativeLocator => $composableBuilder(
    column: $table.relativeLocator,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isDirectory => $composableBuilder(
    column: $table.isDirectory,
    builder: (column) => column,
  );

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<int> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<bool> get available =>
      $composableBuilder(column: $table.available, builder: (column) => column);

  GeneratedColumn<int> get lastSeenScanId => $composableBuilder(
    column: $table.lastSeenScanId,
    builder: (column) => column,
  );

  $$MediaSourcesTableAnnotationComposer get sourceId {
    final $$MediaSourcesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.mediaSources,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaSourcesTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> mediaFilesRefs<T extends Object>(
    Expression<T> Function($$MediaFilesTableAnnotationComposer a) f,
  ) {
    final $$MediaFilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaFiles,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaFilesTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MediaEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaEntriesTable,
          MediaEntryData,
          $$MediaEntriesTableFilterComposer,
          $$MediaEntriesTableOrderingComposer,
          $$MediaEntriesTableAnnotationComposer,
          $$MediaEntriesTableCreateCompanionBuilder,
          $$MediaEntriesTableUpdateCompanionBuilder,
          (MediaEntryData, $$MediaEntriesTableReferences),
          MediaEntryData,
          PrefetchHooks Function({bool sourceId, bool mediaFilesRefs})
        > {
  $$MediaEntriesTableTableManager(_$AppDatabase db, $MediaEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> sourceId = const Value.absent(),
                Value<String> externalEntryId = const Value.absent(),
                Value<String> relativeLocator = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> isDirectory = const Value.absent(),
                Value<int?> size = const Value.absent(),
                Value<int?> modifiedAt = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<bool> available = const Value.absent(),
                Value<int> lastSeenScanId = const Value.absent(),
              }) => MediaEntriesCompanion(
                id: id,
                sourceId: sourceId,
                externalEntryId: externalEntryId,
                relativeLocator: relativeLocator,
                name: name,
                isDirectory: isDirectory,
                size: size,
                modifiedAt: modifiedAt,
                etag: etag,
                available: available,
                lastSeenScanId: lastSeenScanId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int sourceId,
                required String externalEntryId,
                required String relativeLocator,
                required String name,
                required bool isDirectory,
                Value<int?> size = const Value.absent(),
                Value<int?> modifiedAt = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<bool> available = const Value.absent(),
                Value<int> lastSeenScanId = const Value.absent(),
              }) => MediaEntriesCompanion.insert(
                id: id,
                sourceId: sourceId,
                externalEntryId: externalEntryId,
                relativeLocator: relativeLocator,
                name: name,
                isDirectory: isDirectory,
                size: size,
                modifiedAt: modifiedAt,
                etag: etag,
                available: available,
                lastSeenScanId: lastSeenScanId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaEntriesTable, MediaEntryData>(table),
                  $$MediaEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sourceId = false, mediaFilesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (mediaFilesRefs) db.mediaFiles],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sourceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sourceId,
                        referencedTable: $$MediaEntriesTableReferences
                            ._sourceIdTable(db),
                        referencedColumn: $$MediaEntriesTableReferences
                            ._sourceIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (mediaFilesRefs)
                    await $_getPrefetchedData<
                      MediaEntryData,
                      $MediaEntriesTable,
                      MediaFileData
                    >(
                      currentTable: table,
                      referencedTable: $$MediaEntriesTableReferences
                          ._mediaFilesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$MediaEntriesTableReferences(
                            db,
                            table,
                            p0,
                          ).mediaFilesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.entryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$MediaEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaEntriesTable,
      MediaEntryData,
      $$MediaEntriesTableFilterComposer,
      $$MediaEntriesTableOrderingComposer,
      $$MediaEntriesTableAnnotationComposer,
      $$MediaEntriesTableCreateCompanionBuilder,
      $$MediaEntriesTableUpdateCompanionBuilder,
      (MediaEntryData, $$MediaEntriesTableReferences),
      MediaEntryData,
      PrefetchHooks Function({bool sourceId, bool mediaFilesRefs})
    >;
typedef $$MediaFilesTableCreateCompanionBuilder = MediaFilesCompanion Function({
  Value<int> id,
  required int entryId,
  Value<String?> container,
  Value<int?> durationMs,
  Value<int?> resolutionWidth,
  Value<int?> resolutionHeight,
  Value<String?> videoCodec,
  Value<String?> audioCodec,
  Value<String> parseState,
  Value<String?> candidateType,
  Value<int?> candidateSeasonNumber,
  Value<int?> candidateEpisodeNumber,
  Value<String?> candidateDetails,
});
typedef $$MediaFilesTableUpdateCompanionBuilder = MediaFilesCompanion Function({
  Value<int> id,
  Value<int> entryId,
  Value<String?> container,
  Value<int?> durationMs,
  Value<int?> resolutionWidth,
  Value<int?> resolutionHeight,
  Value<String?> videoCodec,
  Value<String?> audioCodec,
  Value<String> parseState,
  Value<String?> candidateType,
  Value<int?> candidateSeasonNumber,
  Value<int?> candidateEpisodeNumber,
  Value<String?> candidateDetails,
});

final class $$MediaFilesTableReferences
    extends BaseReferences<_$AppDatabase, $MediaFilesTable, MediaFileData> {
  $$MediaFilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MediaEntriesTable _entryIdTable(_$AppDatabase db) =>
      db.mediaEntries.createAlias('media_files__entry_id__media_entries__id');

  $$MediaEntriesTableProcessedTableManager get entryId {
    final $_column = $_itemColumn<int>('entry_id')!;

    final manager = $$MediaEntriesTableTableManager(
      $_db,
      $_db.mediaEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_entryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$MediaAssignmentsTable, List<MediaAssignmentData>>
  _mediaAssignmentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mediaAssignments,
    aliasName: 'media_files__id__media_assignments__file_id',
  );

  $$MediaAssignmentsTableProcessedTableManager get mediaAssignmentsRefs {
    final manager = $$MediaAssignmentsTableTableManager(
      $_db,
      $_db.mediaAssignments,
    ).filter((f) => f.fileId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _mediaAssignmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $PlaybackProgressesTable,
    List<PlaybackProgressData>
  >
  _playbackProgressesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.playbackProgresses,
        aliasName: 'media_files__id__playback_progress__last_file_id',
      );

  $$PlaybackProgressesTableProcessedTableManager get playbackProgressesRefs {
    final manager = $$PlaybackProgressesTableTableManager(
      $_db,
      $_db.playbackProgresses,
    ).filter((f) => f.lastFileId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _playbackProgressesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MediaFilesTableFilterComposer
    extends Composer<_$AppDatabase, $MediaFilesTable> {
  $$MediaFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolutionWidth => $composableBuilder(
    column: $table.resolutionWidth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolutionHeight => $composableBuilder(
    column: $table.resolutionHeight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get videoCodec => $composableBuilder(
    column: $table.videoCodec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioCodec => $composableBuilder(
    column: $table.audioCodec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parseState => $composableBuilder(
    column: $table.parseState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get candidateType => $composableBuilder(
    column: $table.candidateType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get candidateSeasonNumber => $composableBuilder(
    column: $table.candidateSeasonNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get candidateEpisodeNumber => $composableBuilder(
    column: $table.candidateEpisodeNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get candidateDetails => $composableBuilder(
    column: $table.candidateDetails,
    builder: (column) => ColumnFilters(column),
  );

  $$MediaEntriesTableFilterComposer get entryId {
    final $$MediaEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.mediaEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaEntriesTableFilterComposer(
            $db: $db,
            $table: $db.mediaEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> mediaAssignmentsRefs(
    Expression<bool> Function($$MediaAssignmentsTableFilterComposer f) f,
  ) {
    final $$MediaAssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaAssignments,
      getReferencedColumn: (t) => t.fileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.mediaAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> playbackProgressesRefs(
    Expression<bool> Function($$PlaybackProgressesTableFilterComposer f) f,
  ) {
    final $$PlaybackProgressesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playbackProgresses,
      getReferencedColumn: (t) => t.lastFileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaybackProgressesTableFilterComposer(
            $db: $db,
            $table: $db.playbackProgresses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MediaFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaFilesTable> {
  $$MediaFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get container => $composableBuilder(
    column: $table.container,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolutionWidth => $composableBuilder(
    column: $table.resolutionWidth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolutionHeight => $composableBuilder(
    column: $table.resolutionHeight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get videoCodec => $composableBuilder(
    column: $table.videoCodec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioCodec => $composableBuilder(
    column: $table.audioCodec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parseState => $composableBuilder(
    column: $table.parseState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get candidateType => $composableBuilder(
    column: $table.candidateType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get candidateSeasonNumber => $composableBuilder(
    column: $table.candidateSeasonNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get candidateEpisodeNumber => $composableBuilder(
    column: $table.candidateEpisodeNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get candidateDetails => $composableBuilder(
    column: $table.candidateDetails,
    builder: (column) => ColumnOrderings(column),
  );

  $$MediaEntriesTableOrderingComposer get entryId {
    final $$MediaEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.mediaEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.mediaEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaFilesTable> {
  $$MediaFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get container =>
      $composableBuilder(column: $table.container, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resolutionWidth => $composableBuilder(
    column: $table.resolutionWidth,
    builder: (column) => column,
  );

  GeneratedColumn<int> get resolutionHeight => $composableBuilder(
    column: $table.resolutionHeight,
    builder: (column) => column,
  );

  GeneratedColumn<String> get videoCodec => $composableBuilder(
    column: $table.videoCodec,
    builder: (column) => column,
  );

  GeneratedColumn<String> get audioCodec => $composableBuilder(
    column: $table.audioCodec,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parseState => $composableBuilder(
    column: $table.parseState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get candidateType => $composableBuilder(
    column: $table.candidateType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get candidateSeasonNumber => $composableBuilder(
    column: $table.candidateSeasonNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get candidateEpisodeNumber => $composableBuilder(
    column: $table.candidateEpisodeNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get candidateDetails => $composableBuilder(
    column: $table.candidateDetails,
    builder: (column) => column,
  );

  $$MediaEntriesTableAnnotationComposer get entryId {
    final $$MediaEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.mediaEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> mediaAssignmentsRefs<T extends Object>(
    Expression<T> Function($$MediaAssignmentsTableAnnotationComposer a) f,
  ) {
    final $$MediaAssignmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaAssignments,
      getReferencedColumn: (t) => t.fileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssignmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> playbackProgressesRefs<T extends Object>(
    Expression<T> Function($$PlaybackProgressesTableAnnotationComposer a) f,
  ) {
    final $$PlaybackProgressesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.playbackProgresses,
          getReferencedColumn: (t) => t.lastFileId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PlaybackProgressesTableAnnotationComposer(
                $db: $db,
                $table: $db.playbackProgresses,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$MediaFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaFilesTable,
          MediaFileData,
          $$MediaFilesTableFilterComposer,
          $$MediaFilesTableOrderingComposer,
          $$MediaFilesTableAnnotationComposer,
          $$MediaFilesTableCreateCompanionBuilder,
          $$MediaFilesTableUpdateCompanionBuilder,
          (MediaFileData, $$MediaFilesTableReferences),
          MediaFileData,
          PrefetchHooks Function({
            bool entryId,
            bool mediaAssignmentsRefs,
            bool playbackProgressesRefs,
          })
        > {
  $$MediaFilesTableTableManager(_$AppDatabase db, $MediaFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> entryId = const Value.absent(),
                Value<String?> container = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> resolutionWidth = const Value.absent(),
                Value<int?> resolutionHeight = const Value.absent(),
                Value<String?> videoCodec = const Value.absent(),
                Value<String?> audioCodec = const Value.absent(),
                Value<String> parseState = const Value.absent(),
                Value<String?> candidateType = const Value.absent(),
                Value<int?> candidateSeasonNumber = const Value.absent(),
                Value<int?> candidateEpisodeNumber = const Value.absent(),
                Value<String?> candidateDetails = const Value.absent(),
              }) => MediaFilesCompanion(
                id: id,
                entryId: entryId,
                container: container,
                durationMs: durationMs,
                resolutionWidth: resolutionWidth,
                resolutionHeight: resolutionHeight,
                videoCodec: videoCodec,
                audioCodec: audioCodec,
                parseState: parseState,
                candidateType: candidateType,
                candidateSeasonNumber: candidateSeasonNumber,
                candidateEpisodeNumber: candidateEpisodeNumber,
                candidateDetails: candidateDetails,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int entryId,
                Value<String?> container = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int?> resolutionWidth = const Value.absent(),
                Value<int?> resolutionHeight = const Value.absent(),
                Value<String?> videoCodec = const Value.absent(),
                Value<String?> audioCodec = const Value.absent(),
                Value<String> parseState = const Value.absent(),
                Value<String?> candidateType = const Value.absent(),
                Value<int?> candidateSeasonNumber = const Value.absent(),
                Value<int?> candidateEpisodeNumber = const Value.absent(),
                Value<String?> candidateDetails = const Value.absent(),
              }) => MediaFilesCompanion.insert(
                id: id,
                entryId: entryId,
                container: container,
                durationMs: durationMs,
                resolutionWidth: resolutionWidth,
                resolutionHeight: resolutionHeight,
                videoCodec: videoCodec,
                audioCodec: audioCodec,
                parseState: parseState,
                candidateType: candidateType,
                candidateSeasonNumber: candidateSeasonNumber,
                candidateEpisodeNumber: candidateEpisodeNumber,
                candidateDetails: candidateDetails,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaFilesTable, MediaFileData>(table),
                  $$MediaFilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                entryId = false,
                mediaAssignmentsRefs = false,
                playbackProgressesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mediaAssignmentsRefs) db.mediaAssignments,
                    if (playbackProgressesRefs) db.playbackProgresses,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (entryId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.entryId,
                            referencedTable: $$MediaFilesTableReferences
                                ._entryIdTable(db),
                            referencedColumn: $$MediaFilesTableReferences
                                ._entryIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (mediaAssignmentsRefs)
                        await $_getPrefetchedData<
                          MediaFileData,
                          $MediaFilesTable,
                          MediaAssignmentData
                        >(
                          currentTable: table,
                          referencedTable: $$MediaFilesTableReferences
                              ._mediaAssignmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MediaFilesTableReferences(
                                db,
                                table,
                                p0,
                              ).mediaAssignmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.fileId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (playbackProgressesRefs)
                        await $_getPrefetchedData<
                          MediaFileData,
                          $MediaFilesTable,
                          PlaybackProgressData
                        >(
                          currentTable: table,
                          referencedTable: $$MediaFilesTableReferences
                              ._playbackProgressesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MediaFilesTableReferences(
                                db,
                                table,
                                p0,
                              ).playbackProgressesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.lastFileId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MediaFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaFilesTable,
      MediaFileData,
      $$MediaFilesTableFilterComposer,
      $$MediaFilesTableOrderingComposer,
      $$MediaFilesTableAnnotationComposer,
      $$MediaFilesTableCreateCompanionBuilder,
      $$MediaFilesTableUpdateCompanionBuilder,
      (MediaFileData, $$MediaFilesTableReferences),
      MediaFileData,
      PrefetchHooks Function({
        bool entryId,
        bool mediaAssignmentsRefs,
        bool playbackProgressesRefs,
      })
    >;
typedef $$WorksTableCreateCompanionBuilder = WorksCompanion Function({
  Value<int> id,
  Value<String?> type,
  required String title,
  Value<String?> originalTitle,
  Value<int?> year,
  Value<String?> overview,
  Value<String?> posterPath,
  Value<String?> backdropPath,
  Value<String> metadataSource,
  Value<bool> metadataLocked,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$WorksTableUpdateCompanionBuilder = WorksCompanion Function({
  Value<int> id,
  Value<String?> type,
  Value<String> title,
  Value<String?> originalTitle,
  Value<int?> year,
  Value<String?> overview,
  Value<String?> posterPath,
  Value<String?> backdropPath,
  Value<String> metadataSource,
  Value<bool> metadataLocked,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$WorksTableReferences
    extends BaseReferences<_$AppDatabase, $WorksTable, WorkData> {
  $$WorksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SeasonsTable, List<SeasonData>> _seasonsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.seasons,
    aliasName: 'works__id__seasons__series_id',
  );

  $$SeasonsTableProcessedTableManager get seasonsRefs {
    final manager = $$SeasonsTableTableManager(
      $_db,
      $_db.seasons,
    ).filter((f) => f.seriesId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_seasonsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MediaAssignmentsTable, List<MediaAssignmentData>>
  _mediaAssignmentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mediaAssignments,
    aliasName: 'works__id__media_assignments__work_id',
  );

  $$MediaAssignmentsTableProcessedTableManager get mediaAssignmentsRefs {
    final manager = $$MediaAssignmentsTableTableManager(
      $_db,
      $_db.mediaAssignments,
    ).filter((f) => f.workId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _mediaAssignmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $PlaybackProgressesTable,
    List<PlaybackProgressData>
  >
  _playbackProgressesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.playbackProgresses,
        aliasName: 'works__id__playback_progress__work_id',
      );

  $$PlaybackProgressesTableProcessedTableManager get playbackProgressesRefs {
    final manager = $$PlaybackProgressesTableTableManager(
      $_db,
      $_db.playbackProgresses,
    ).filter((f) => f.workId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _playbackProgressesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ExternalIdsTable, List<ExternalIdData>>
  _externalIdsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.externalIds,
    aliasName: 'works__id__external_ids__work_id',
  );

  $$ExternalIdsTableProcessedTableManager get externalIdsRefs {
    final manager = $$ExternalIdsTableTableManager(
      $_db,
      $_db.externalIds,
    ).filter((f) => f.workId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_externalIdsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$WorksTableFilterComposer extends Composer<_$AppDatabase, $WorksTable> {
  $$WorksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalTitle => $composableBuilder(
    column: $table.originalTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get overview => $composableBuilder(
    column: $table.overview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get posterPath => $composableBuilder(
    column: $table.posterPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataSource => $composableBuilder(
    column: $table.metadataSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get metadataLocked => $composableBuilder(
    column: $table.metadataLocked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> seasonsRefs(
    Expression<bool> Function($$SeasonsTableFilterComposer f) f,
  ) {
    final $$SeasonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.seasons,
      getReferencedColumn: (t) => t.seriesId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeasonsTableFilterComposer(
            $db: $db,
            $table: $db.seasons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mediaAssignmentsRefs(
    Expression<bool> Function($$MediaAssignmentsTableFilterComposer f) f,
  ) {
    final $$MediaAssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaAssignments,
      getReferencedColumn: (t) => t.workId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.mediaAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> playbackProgressesRefs(
    Expression<bool> Function($$PlaybackProgressesTableFilterComposer f) f,
  ) {
    final $$PlaybackProgressesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playbackProgresses,
      getReferencedColumn: (t) => t.workId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaybackProgressesTableFilterComposer(
            $db: $db,
            $table: $db.playbackProgresses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> externalIdsRefs(
    Expression<bool> Function($$ExternalIdsTableFilterComposer f) f,
  ) {
    final $$ExternalIdsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.externalIds,
      getReferencedColumn: (t) => t.workId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalIdsTableFilterComposer(
            $db: $db,
            $table: $db.externalIds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WorksTableOrderingComposer
    extends Composer<_$AppDatabase, $WorksTable> {
  $$WorksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalTitle => $composableBuilder(
    column: $table.originalTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get overview => $composableBuilder(
    column: $table.overview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get posterPath => $composableBuilder(
    column: $table.posterPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataSource => $composableBuilder(
    column: $table.metadataSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get metadataLocked => $composableBuilder(
    column: $table.metadataLocked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorksTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorksTable> {
  $$WorksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get originalTitle => $composableBuilder(
    column: $table.originalTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<String> get overview =>
      $composableBuilder(column: $table.overview, builder: (column) => column);

  GeneratedColumn<String> get posterPath => $composableBuilder(
    column: $table.posterPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataSource => $composableBuilder(
    column: $table.metadataSource,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get metadataLocked => $composableBuilder(
    column: $table.metadataLocked,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> seasonsRefs<T extends Object>(
    Expression<T> Function($$SeasonsTableAnnotationComposer a) f,
  ) {
    final $$SeasonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.seasons,
      getReferencedColumn: (t) => t.seriesId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeasonsTableAnnotationComposer(
            $db: $db,
            $table: $db.seasons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mediaAssignmentsRefs<T extends Object>(
    Expression<T> Function($$MediaAssignmentsTableAnnotationComposer a) f,
  ) {
    final $$MediaAssignmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaAssignments,
      getReferencedColumn: (t) => t.workId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssignmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> playbackProgressesRefs<T extends Object>(
    Expression<T> Function($$PlaybackProgressesTableAnnotationComposer a) f,
  ) {
    final $$PlaybackProgressesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.playbackProgresses,
          getReferencedColumn: (t) => t.workId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PlaybackProgressesTableAnnotationComposer(
                $db: $db,
                $table: $db.playbackProgresses,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> externalIdsRefs<T extends Object>(
    Expression<T> Function($$ExternalIdsTableAnnotationComposer a) f,
  ) {
    final $$ExternalIdsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.externalIds,
      getReferencedColumn: (t) => t.workId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalIdsTableAnnotationComposer(
            $db: $db,
            $table: $db.externalIds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WorksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorksTable,
          WorkData,
          $$WorksTableFilterComposer,
          $$WorksTableOrderingComposer,
          $$WorksTableAnnotationComposer,
          $$WorksTableCreateCompanionBuilder,
          $$WorksTableUpdateCompanionBuilder,
          (WorkData, $$WorksTableReferences),
          WorkData,
          PrefetchHooks Function({
            bool seasonsRefs,
            bool mediaAssignmentsRefs,
            bool playbackProgressesRefs,
            bool externalIdsRefs,
          })
        > {
  $$WorksTableTableManager(_$AppDatabase db, $WorksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> originalTitle = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> overview = const Value.absent(),
                Value<String?> posterPath = const Value.absent(),
                Value<String?> backdropPath = const Value.absent(),
                Value<String> metadataSource = const Value.absent(),
                Value<bool> metadataLocked = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => WorksCompanion(
                id: id,
                type: type,
                title: title,
                originalTitle: originalTitle,
                year: year,
                overview: overview,
                posterPath: posterPath,
                backdropPath: backdropPath,
                metadataSource: metadataSource,
                metadataLocked: metadataLocked,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> type = const Value.absent(),
                required String title,
                Value<String?> originalTitle = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<String?> overview = const Value.absent(),
                Value<String?> posterPath = const Value.absent(),
                Value<String?> backdropPath = const Value.absent(),
                Value<String> metadataSource = const Value.absent(),
                Value<bool> metadataLocked = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => WorksCompanion.insert(
                id: id,
                type: type,
                title: title,
                originalTitle: originalTitle,
                year: year,
                overview: overview,
                posterPath: posterPath,
                backdropPath: backdropPath,
                metadataSource: metadataSource,
                metadataLocked: metadataLocked,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorksTable, WorkData>(table),
                  $$WorksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                seasonsRefs = false,
                mediaAssignmentsRefs = false,
                playbackProgressesRefs = false,
                externalIdsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (seasonsRefs) db.seasons,
                    if (mediaAssignmentsRefs) db.mediaAssignments,
                    if (playbackProgressesRefs) db.playbackProgresses,
                    if (externalIdsRefs) db.externalIds,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (seasonsRefs)
                        await $_getPrefetchedData<
                          WorkData,
                          $WorksTable,
                          SeasonData
                        >(
                          currentTable: table,
                          referencedTable: $$WorksTableReferences
                              ._seasonsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorksTableReferences(db, table, p0).seasonsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.seriesId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (mediaAssignmentsRefs)
                        await $_getPrefetchedData<
                          WorkData,
                          $WorksTable,
                          MediaAssignmentData
                        >(
                          currentTable: table,
                          referencedTable: $$WorksTableReferences
                              ._mediaAssignmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorksTableReferences(
                                db,
                                table,
                                p0,
                              ).mediaAssignmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (playbackProgressesRefs)
                        await $_getPrefetchedData<
                          WorkData,
                          $WorksTable,
                          PlaybackProgressData
                        >(
                          currentTable: table,
                          referencedTable: $$WorksTableReferences
                              ._playbackProgressesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorksTableReferences(
                                db,
                                table,
                                p0,
                              ).playbackProgressesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (externalIdsRefs)
                        await $_getPrefetchedData<
                          WorkData,
                          $WorksTable,
                          ExternalIdData
                        >(
                          currentTable: table,
                          referencedTable: $$WorksTableReferences
                              ._externalIdsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$WorksTableReferences(
                                db,
                                table,
                                p0,
                              ).externalIdsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.workId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$WorksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorksTable,
      WorkData,
      $$WorksTableFilterComposer,
      $$WorksTableOrderingComposer,
      $$WorksTableAnnotationComposer,
      $$WorksTableCreateCompanionBuilder,
      $$WorksTableUpdateCompanionBuilder,
      (WorkData, $$WorksTableReferences),
      WorkData,
      PrefetchHooks Function({
        bool seasonsRefs,
        bool mediaAssignmentsRefs,
        bool playbackProgressesRefs,
        bool externalIdsRefs,
      })
    >;
typedef $$SeasonsTableCreateCompanionBuilder = SeasonsCompanion Function({
  Value<int> id,
  required int seriesId,
  required int seasonNumber,
  Value<String?> title,
});
typedef $$SeasonsTableUpdateCompanionBuilder = SeasonsCompanion Function({
  Value<int> id,
  Value<int> seriesId,
  Value<int> seasonNumber,
  Value<String?> title,
});

final class $$SeasonsTableReferences
    extends BaseReferences<_$AppDatabase, $SeasonsTable, SeasonData> {
  $$SeasonsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorksTable _seriesIdTable(_$AppDatabase db) =>
      db.works.createAlias('seasons__series_id__works__id');

  $$WorksTableProcessedTableManager get seriesId {
    final $_column = $_itemColumn<int>('series_id')!;

    final manager = $$WorksTableTableManager(
      $_db,
      $_db.works,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_seriesIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$EpisodesTable, List<EpisodeData>>
  _episodesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.episodes,
    aliasName: 'seasons__id__episodes__season_id',
  );

  $$EpisodesTableProcessedTableManager get episodesRefs {
    final manager = $$EpisodesTableTableManager(
      $_db,
      $_db.episodes,
    ).filter((f) => f.seasonId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_episodesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SeasonsTableFilterComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  $$WorksTableFilterComposer get seriesId {
    final $$WorksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seriesId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableFilterComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> episodesRefs(
    Expression<bool> Function($$EpisodesTableFilterComposer f) f,
  ) {
    final $$EpisodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.episodes,
      getReferencedColumn: (t) => t.seasonId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EpisodesTableFilterComposer(
            $db: $db,
            $table: $db.episodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SeasonsTableOrderingComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorksTableOrderingComposer get seriesId {
    final $$WorksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seriesId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableOrderingComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SeasonsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  $$WorksTableAnnotationComposer get seriesId {
    final $$WorksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seriesId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableAnnotationComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> episodesRefs<T extends Object>(
    Expression<T> Function($$EpisodesTableAnnotationComposer a) f,
  ) {
    final $$EpisodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.episodes,
      getReferencedColumn: (t) => t.seasonId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EpisodesTableAnnotationComposer(
            $db: $db,
            $table: $db.episodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SeasonsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeasonsTable,
          SeasonData,
          $$SeasonsTableFilterComposer,
          $$SeasonsTableOrderingComposer,
          $$SeasonsTableAnnotationComposer,
          $$SeasonsTableCreateCompanionBuilder,
          $$SeasonsTableUpdateCompanionBuilder,
          (SeasonData, $$SeasonsTableReferences),
          SeasonData,
          PrefetchHooks Function({bool seriesId, bool episodesRefs})
        > {
  $$SeasonsTableTableManager(_$AppDatabase db, $SeasonsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeasonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeasonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeasonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> seriesId = const Value.absent(),
                Value<int> seasonNumber = const Value.absent(),
                Value<String?> title = const Value.absent(),
              }) => SeasonsCompanion(
                id: id,
                seriesId: seriesId,
                seasonNumber: seasonNumber,
                title: title,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int seriesId,
                required int seasonNumber,
                Value<String?> title = const Value.absent(),
              }) => SeasonsCompanion.insert(
                id: id,
                seriesId: seriesId,
                seasonNumber: seasonNumber,
                title: title,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SeasonsTable, SeasonData>(table),
                  $$SeasonsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({seriesId = false, episodesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (episodesRefs) db.episodes],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (seriesId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.seriesId,
                        referencedTable: $$SeasonsTableReferences
                            ._seriesIdTable(db),
                        referencedColumn: $$SeasonsTableReferences
                            ._seriesIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (episodesRefs)
                    await $_getPrefetchedData<
                      SeasonData,
                      $SeasonsTable,
                      EpisodeData
                    >(
                      currentTable: table,
                      referencedTable: $$SeasonsTableReferences
                          ._episodesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$SeasonsTableReferences(db, table, p0).episodesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.seasonId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SeasonsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeasonsTable,
      SeasonData,
      $$SeasonsTableFilterComposer,
      $$SeasonsTableOrderingComposer,
      $$SeasonsTableAnnotationComposer,
      $$SeasonsTableCreateCompanionBuilder,
      $$SeasonsTableUpdateCompanionBuilder,
      (SeasonData, $$SeasonsTableReferences),
      SeasonData,
      PrefetchHooks Function({bool seriesId, bool episodesRefs})
    >;
typedef $$EpisodesTableCreateCompanionBuilder = EpisodesCompanion Function({
  Value<int> id,
  required int seasonId,
  required int episodeNumber,
  Value<String?> title,
  Value<String?> overview,
  Value<DateTime?> airDate,
});
typedef $$EpisodesTableUpdateCompanionBuilder = EpisodesCompanion Function({
  Value<int> id,
  Value<int> seasonId,
  Value<int> episodeNumber,
  Value<String?> title,
  Value<String?> overview,
  Value<DateTime?> airDate,
});

final class $$EpisodesTableReferences
    extends BaseReferences<_$AppDatabase, $EpisodesTable, EpisodeData> {
  $$EpisodesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SeasonsTable _seasonIdTable(_$AppDatabase db) =>
      db.seasons.createAlias('episodes__season_id__seasons__id');

  $$SeasonsTableProcessedTableManager get seasonId {
    final $_column = $_itemColumn<int>('season_id')!;

    final manager = $$SeasonsTableTableManager(
      $_db,
      $_db.seasons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_seasonIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$MediaAssignmentsTable, List<MediaAssignmentData>>
  _mediaAssignmentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mediaAssignments,
    aliasName: 'episodes__id__media_assignments__episode_id',
  );

  $$MediaAssignmentsTableProcessedTableManager get mediaAssignmentsRefs {
    final manager = $$MediaAssignmentsTableTableManager(
      $_db,
      $_db.mediaAssignments,
    ).filter((f) => f.episodeId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _mediaAssignmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $PlaybackProgressesTable,
    List<PlaybackProgressData>
  >
  _playbackProgressesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.playbackProgresses,
        aliasName: 'episodes__id__playback_progress__episode_id',
      );

  $$PlaybackProgressesTableProcessedTableManager get playbackProgressesRefs {
    final manager = $$PlaybackProgressesTableTableManager(
      $_db,
      $_db.playbackProgresses,
    ).filter((f) => f.episodeId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _playbackProgressesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$EpisodesTableFilterComposer
    extends Composer<_$AppDatabase, $EpisodesTable> {
  $$EpisodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get overview => $composableBuilder(
    column: $table.overview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get airDate => $composableBuilder(
    column: $table.airDate,
    builder: (column) => ColumnFilters(column),
  );

  $$SeasonsTableFilterComposer get seasonId {
    final $$SeasonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seasonId,
      referencedTable: $db.seasons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeasonsTableFilterComposer(
            $db: $db,
            $table: $db.seasons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> mediaAssignmentsRefs(
    Expression<bool> Function($$MediaAssignmentsTableFilterComposer f) f,
  ) {
    final $$MediaAssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaAssignments,
      getReferencedColumn: (t) => t.episodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.mediaAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> playbackProgressesRefs(
    Expression<bool> Function($$PlaybackProgressesTableFilterComposer f) f,
  ) {
    final $$PlaybackProgressesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playbackProgresses,
      getReferencedColumn: (t) => t.episodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaybackProgressesTableFilterComposer(
            $db: $db,
            $table: $db.playbackProgresses,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EpisodesTableOrderingComposer
    extends Composer<_$AppDatabase, $EpisodesTable> {
  $$EpisodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get overview => $composableBuilder(
    column: $table.overview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get airDate => $composableBuilder(
    column: $table.airDate,
    builder: (column) => ColumnOrderings(column),
  );

  $$SeasonsTableOrderingComposer get seasonId {
    final $$SeasonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seasonId,
      referencedTable: $db.seasons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeasonsTableOrderingComposer(
            $db: $db,
            $table: $db.seasons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EpisodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EpisodesTable> {
  $$EpisodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get overview =>
      $composableBuilder(column: $table.overview, builder: (column) => column);

  GeneratedColumn<DateTime> get airDate =>
      $composableBuilder(column: $table.airDate, builder: (column) => column);

  $$SeasonsTableAnnotationComposer get seasonId {
    final $$SeasonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seasonId,
      referencedTable: $db.seasons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeasonsTableAnnotationComposer(
            $db: $db,
            $table: $db.seasons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> mediaAssignmentsRefs<T extends Object>(
    Expression<T> Function($$MediaAssignmentsTableAnnotationComposer a) f,
  ) {
    final $$MediaAssignmentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaAssignments,
      getReferencedColumn: (t) => t.episodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssignmentsTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> playbackProgressesRefs<T extends Object>(
    Expression<T> Function($$PlaybackProgressesTableAnnotationComposer a) f,
  ) {
    final $$PlaybackProgressesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.playbackProgresses,
          getReferencedColumn: (t) => t.episodeId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PlaybackProgressesTableAnnotationComposer(
                $db: $db,
                $table: $db.playbackProgresses,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$EpisodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EpisodesTable,
          EpisodeData,
          $$EpisodesTableFilterComposer,
          $$EpisodesTableOrderingComposer,
          $$EpisodesTableAnnotationComposer,
          $$EpisodesTableCreateCompanionBuilder,
          $$EpisodesTableUpdateCompanionBuilder,
          (EpisodeData, $$EpisodesTableReferences),
          EpisodeData,
          PrefetchHooks Function({
            bool seasonId,
            bool mediaAssignmentsRefs,
            bool playbackProgressesRefs,
          })
        > {
  $$EpisodesTableTableManager(_$AppDatabase db, $EpisodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EpisodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EpisodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EpisodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> seasonId = const Value.absent(),
                Value<int> episodeNumber = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> overview = const Value.absent(),
                Value<DateTime?> airDate = const Value.absent(),
              }) => EpisodesCompanion(
                id: id,
                seasonId: seasonId,
                episodeNumber: episodeNumber,
                title: title,
                overview: overview,
                airDate: airDate,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int seasonId,
                required int episodeNumber,
                Value<String?> title = const Value.absent(),
                Value<String?> overview = const Value.absent(),
                Value<DateTime?> airDate = const Value.absent(),
              }) => EpisodesCompanion.insert(
                id: id,
                seasonId: seasonId,
                episodeNumber: episodeNumber,
                title: title,
                overview: overview,
                airDate: airDate,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EpisodesTable, EpisodeData>(table),
                  $$EpisodesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                seasonId = false,
                mediaAssignmentsRefs = false,
                playbackProgressesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mediaAssignmentsRefs) db.mediaAssignments,
                    if (playbackProgressesRefs) db.playbackProgresses,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (seasonId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.seasonId,
                            referencedTable: $$EpisodesTableReferences
                                ._seasonIdTable(db),
                            referencedColumn: $$EpisodesTableReferences
                                ._seasonIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (mediaAssignmentsRefs)
                        await $_getPrefetchedData<
                          EpisodeData,
                          $EpisodesTable,
                          MediaAssignmentData
                        >(
                          currentTable: table,
                          referencedTable: $$EpisodesTableReferences
                              ._mediaAssignmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EpisodesTableReferences(
                                db,
                                table,
                                p0,
                              ).mediaAssignmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.episodeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (playbackProgressesRefs)
                        await $_getPrefetchedData<
                          EpisodeData,
                          $EpisodesTable,
                          PlaybackProgressData
                        >(
                          currentTable: table,
                          referencedTable: $$EpisodesTableReferences
                              ._playbackProgressesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EpisodesTableReferences(
                                db,
                                table,
                                p0,
                              ).playbackProgressesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.episodeId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$EpisodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EpisodesTable,
      EpisodeData,
      $$EpisodesTableFilterComposer,
      $$EpisodesTableOrderingComposer,
      $$EpisodesTableAnnotationComposer,
      $$EpisodesTableCreateCompanionBuilder,
      $$EpisodesTableUpdateCompanionBuilder,
      (EpisodeData, $$EpisodesTableReferences),
      EpisodeData,
      PrefetchHooks Function({
        bool seasonId,
        bool mediaAssignmentsRefs,
        bool playbackProgressesRefs,
      })
    >;
typedef $$MediaAssignmentsTableCreateCompanionBuilder =
    MediaAssignmentsCompanion Function({
      Value<int> id,
      required int fileId,
      Value<int?> workId,
      Value<int?> episodeId,
      Value<String?> editionLabel,
      Value<bool> preferred,
    });
typedef $$MediaAssignmentsTableUpdateCompanionBuilder =
    MediaAssignmentsCompanion Function({
      Value<int> id,
      Value<int> fileId,
      Value<int?> workId,
      Value<int?> episodeId,
      Value<String?> editionLabel,
      Value<bool> preferred,
    });

final class $$MediaAssignmentsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $MediaAssignmentsTable,
          MediaAssignmentData
        > {
  $$MediaAssignmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MediaFilesTable _fileIdTable(_$AppDatabase db) =>
      db.mediaFiles.createAlias('media_assignments__file_id__media_files__id');

  $$MediaFilesTableProcessedTableManager get fileId {
    final $_column = $_itemColumn<int>('file_id')!;

    final manager = $$MediaFilesTableTableManager(
      $_db,
      $_db.mediaFiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $WorksTable _workIdTable(_$AppDatabase db) =>
      db.works.createAlias('media_assignments__work_id__works__id');

  $$WorksTableProcessedTableManager? get workId {
    final $_column = $_itemColumn<int>('work_id');
    if ($_column == null) return null;
    final manager = $$WorksTableTableManager(
      $_db,
      $_db.works,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $EpisodesTable _episodeIdTable(_$AppDatabase db) =>
      db.episodes.createAlias('media_assignments__episode_id__episodes__id');

  $$EpisodesTableProcessedTableManager? get episodeId {
    final $_column = $_itemColumn<int>('episode_id');
    if ($_column == null) return null;
    final manager = $$EpisodesTableTableManager(
      $_db,
      $_db.episodes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_episodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MediaAssignmentsTableFilterComposer
    extends Composer<_$AppDatabase, $MediaAssignmentsTable> {
  $$MediaAssignmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get editionLabel => $composableBuilder(
    column: $table.editionLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get preferred => $composableBuilder(
    column: $table.preferred,
    builder: (column) => ColumnFilters(column),
  );

  $$MediaFilesTableFilterComposer get fileId {
    final $$MediaFilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fileId,
      referencedTable: $db.mediaFiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaFilesTableFilterComposer(
            $db: $db,
            $table: $db.mediaFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WorksTableFilterComposer get workId {
    final $$WorksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableFilterComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EpisodesTableFilterComposer get episodeId {
    final $$EpisodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.episodeId,
      referencedTable: $db.episodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EpisodesTableFilterComposer(
            $db: $db,
            $table: $db.episodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaAssignmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaAssignmentsTable> {
  $$MediaAssignmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get editionLabel => $composableBuilder(
    column: $table.editionLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get preferred => $composableBuilder(
    column: $table.preferred,
    builder: (column) => ColumnOrderings(column),
  );

  $$MediaFilesTableOrderingComposer get fileId {
    final $$MediaFilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fileId,
      referencedTable: $db.mediaFiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaFilesTableOrderingComposer(
            $db: $db,
            $table: $db.mediaFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WorksTableOrderingComposer get workId {
    final $$WorksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableOrderingComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EpisodesTableOrderingComposer get episodeId {
    final $$EpisodesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.episodeId,
      referencedTable: $db.episodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EpisodesTableOrderingComposer(
            $db: $db,
            $table: $db.episodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaAssignmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaAssignmentsTable> {
  $$MediaAssignmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get editionLabel => $composableBuilder(
    column: $table.editionLabel,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get preferred =>
      $composableBuilder(column: $table.preferred, builder: (column) => column);

  $$MediaFilesTableAnnotationComposer get fileId {
    final $$MediaFilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fileId,
      referencedTable: $db.mediaFiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaFilesTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$WorksTableAnnotationComposer get workId {
    final $$WorksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableAnnotationComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EpisodesTableAnnotationComposer get episodeId {
    final $$EpisodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.episodeId,
      referencedTable: $db.episodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EpisodesTableAnnotationComposer(
            $db: $db,
            $table: $db.episodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaAssignmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaAssignmentsTable,
          MediaAssignmentData,
          $$MediaAssignmentsTableFilterComposer,
          $$MediaAssignmentsTableOrderingComposer,
          $$MediaAssignmentsTableAnnotationComposer,
          $$MediaAssignmentsTableCreateCompanionBuilder,
          $$MediaAssignmentsTableUpdateCompanionBuilder,
          (MediaAssignmentData, $$MediaAssignmentsTableReferences),
          MediaAssignmentData,
          PrefetchHooks Function({bool fileId, bool workId, bool episodeId})
        > {
  $$MediaAssignmentsTableTableManager(
    _$AppDatabase db,
    $MediaAssignmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaAssignmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaAssignmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaAssignmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> fileId = const Value.absent(),
                Value<int?> workId = const Value.absent(),
                Value<int?> episodeId = const Value.absent(),
                Value<String?> editionLabel = const Value.absent(),
                Value<bool> preferred = const Value.absent(),
              }) => MediaAssignmentsCompanion(
                id: id,
                fileId: fileId,
                workId: workId,
                episodeId: episodeId,
                editionLabel: editionLabel,
                preferred: preferred,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int fileId,
                Value<int?> workId = const Value.absent(),
                Value<int?> episodeId = const Value.absent(),
                Value<String?> editionLabel = const Value.absent(),
                Value<bool> preferred = const Value.absent(),
              }) => MediaAssignmentsCompanion.insert(
                id: id,
                fileId: fileId,
                workId: workId,
                episodeId: episodeId,
                editionLabel: editionLabel,
                preferred: preferred,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaAssignmentsTable, MediaAssignmentData>(
                    table,
                  ),
                  $$MediaAssignmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({fileId = false, workId = false, episodeId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (fileId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.fileId,
                            referencedTable: $$MediaAssignmentsTableReferences
                                ._fileIdTable(db),
                            referencedColumn: $$MediaAssignmentsTableReferences
                                ._fileIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (workId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.workId,
                            referencedTable: $$MediaAssignmentsTableReferences
                                ._workIdTable(db),
                            referencedColumn: $$MediaAssignmentsTableReferences
                                ._workIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (episodeId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.episodeId,
                            referencedTable: $$MediaAssignmentsTableReferences
                                ._episodeIdTable(db),
                            referencedColumn: $$MediaAssignmentsTableReferences
                                ._episodeIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$MediaAssignmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaAssignmentsTable,
      MediaAssignmentData,
      $$MediaAssignmentsTableFilterComposer,
      $$MediaAssignmentsTableOrderingComposer,
      $$MediaAssignmentsTableAnnotationComposer,
      $$MediaAssignmentsTableCreateCompanionBuilder,
      $$MediaAssignmentsTableUpdateCompanionBuilder,
      (MediaAssignmentData, $$MediaAssignmentsTableReferences),
      MediaAssignmentData,
      PrefetchHooks Function({bool fileId, bool workId, bool episodeId})
    >;
typedef $$PlaybackProgressesTableCreateCompanionBuilder =
    PlaybackProgressesCompanion Function({
      Value<int> id,
      required String targetType,
      required int targetId,
      Value<int?> workId,
      Value<int?> episodeId,
      Value<int?> lastFileId,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<bool> completed,
      Value<DateTime> updatedAt,
    });
typedef $$PlaybackProgressesTableUpdateCompanionBuilder =
    PlaybackProgressesCompanion Function({
      Value<int> id,
      Value<String> targetType,
      Value<int> targetId,
      Value<int?> workId,
      Value<int?> episodeId,
      Value<int?> lastFileId,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<bool> completed,
      Value<DateTime> updatedAt,
    });

final class $$PlaybackProgressesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $PlaybackProgressesTable,
          PlaybackProgressData
        > {
  $$PlaybackProgressesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WorksTable _workIdTable(_$AppDatabase db) =>
      db.works.createAlias('playback_progress__work_id__works__id');

  $$WorksTableProcessedTableManager? get workId {
    final $_column = $_itemColumn<int>('work_id');
    if ($_column == null) return null;
    final manager = $$WorksTableTableManager(
      $_db,
      $_db.works,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $EpisodesTable _episodeIdTable(_$AppDatabase db) =>
      db.episodes.createAlias('playback_progress__episode_id__episodes__id');

  $$EpisodesTableProcessedTableManager? get episodeId {
    final $_column = $_itemColumn<int>('episode_id');
    if ($_column == null) return null;
    final manager = $$EpisodesTableTableManager(
      $_db,
      $_db.episodes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_episodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MediaFilesTable _lastFileIdTable(_$AppDatabase db) => db.mediaFiles
      .createAlias('playback_progress__last_file_id__media_files__id');

  $$MediaFilesTableProcessedTableManager? get lastFileId {
    final $_column = $_itemColumn<int>('last_file_id');
    if ($_column == null) return null;
    final manager = $$MediaFilesTableTableManager(
      $_db,
      $_db.mediaFiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_lastFileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlaybackProgressesTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackProgressesTable> {
  $$PlaybackProgressesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WorksTableFilterComposer get workId {
    final $$WorksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableFilterComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EpisodesTableFilterComposer get episodeId {
    final $$EpisodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.episodeId,
      referencedTable: $db.episodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EpisodesTableFilterComposer(
            $db: $db,
            $table: $db.episodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MediaFilesTableFilterComposer get lastFileId {
    final $$MediaFilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.lastFileId,
      referencedTable: $db.mediaFiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaFilesTableFilterComposer(
            $db: $db,
            $table: $db.mediaFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaybackProgressesTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackProgressesTable> {
  $$PlaybackProgressesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorksTableOrderingComposer get workId {
    final $$WorksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableOrderingComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EpisodesTableOrderingComposer get episodeId {
    final $$EpisodesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.episodeId,
      referencedTable: $db.episodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EpisodesTableOrderingComposer(
            $db: $db,
            $table: $db.episodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MediaFilesTableOrderingComposer get lastFileId {
    final $$MediaFilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.lastFileId,
      referencedTable: $db.mediaFiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaFilesTableOrderingComposer(
            $db: $db,
            $table: $db.mediaFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaybackProgressesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackProgressesTable> {
  $$PlaybackProgressesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get targetType => $composableBuilder(
    column: $table.targetType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$WorksTableAnnotationComposer get workId {
    final $$WorksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableAnnotationComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EpisodesTableAnnotationComposer get episodeId {
    final $$EpisodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.episodeId,
      referencedTable: $db.episodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EpisodesTableAnnotationComposer(
            $db: $db,
            $table: $db.episodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MediaFilesTableAnnotationComposer get lastFileId {
    final $$MediaFilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.lastFileId,
      referencedTable: $db.mediaFiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaFilesTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaybackProgressesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaybackProgressesTable,
          PlaybackProgressData,
          $$PlaybackProgressesTableFilterComposer,
          $$PlaybackProgressesTableOrderingComposer,
          $$PlaybackProgressesTableAnnotationComposer,
          $$PlaybackProgressesTableCreateCompanionBuilder,
          $$PlaybackProgressesTableUpdateCompanionBuilder,
          (PlaybackProgressData, $$PlaybackProgressesTableReferences),
          PlaybackProgressData,
          PrefetchHooks Function({bool workId, bool episodeId, bool lastFileId})
        > {
  $$PlaybackProgressesTableTableManager(
    _$AppDatabase db,
    $PlaybackProgressesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackProgressesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaybackProgressesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaybackProgressesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> targetType = const Value.absent(),
                Value<int> targetId = const Value.absent(),
                Value<int?> workId = const Value.absent(),
                Value<int?> episodeId = const Value.absent(),
                Value<int?> lastFileId = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PlaybackProgressesCompanion(
                id: id,
                targetType: targetType,
                targetId: targetId,
                workId: workId,
                episodeId: episodeId,
                lastFileId: lastFileId,
                positionMs: positionMs,
                durationMs: durationMs,
                completed: completed,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String targetType,
                required int targetId,
                Value<int?> workId = const Value.absent(),
                Value<int?> episodeId = const Value.absent(),
                Value<int?> lastFileId = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PlaybackProgressesCompanion.insert(
                id: id,
                targetType: targetType,
                targetId: targetId,
                workId: workId,
                episodeId: episodeId,
                lastFileId: lastFileId,
                positionMs: positionMs,
                durationMs: durationMs,
                completed: completed,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlaybackProgressesTable, PlaybackProgressData>(
                    table,
                  ),
                  $$PlaybackProgressesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({workId = false, episodeId = false, lastFileId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (workId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.workId,
                            referencedTable: $$PlaybackProgressesTableReferences
                                ._workIdTable(db),
                            referencedColumn:
                                $$PlaybackProgressesTableReferences
                                    ._workIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (episodeId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.episodeId,
                            referencedTable: $$PlaybackProgressesTableReferences
                                ._episodeIdTable(db),
                            referencedColumn:
                                $$PlaybackProgressesTableReferences
                                    ._episodeIdTable(db)
                                    .id,
                          ) as T;
                        }
                        if (lastFileId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.lastFileId,
                            referencedTable: $$PlaybackProgressesTableReferences
                                ._lastFileIdTable(db),
                            referencedColumn:
                                $$PlaybackProgressesTableReferences
                                    ._lastFileIdTable(db)
                                    .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$PlaybackProgressesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaybackProgressesTable,
      PlaybackProgressData,
      $$PlaybackProgressesTableFilterComposer,
      $$PlaybackProgressesTableOrderingComposer,
      $$PlaybackProgressesTableAnnotationComposer,
      $$PlaybackProgressesTableCreateCompanionBuilder,
      $$PlaybackProgressesTableUpdateCompanionBuilder,
      (PlaybackProgressData, $$PlaybackProgressesTableReferences),
      PlaybackProgressData,
      PrefetchHooks Function({bool workId, bool episodeId, bool lastFileId})
    >;
typedef $$ExternalIdsTableCreateCompanionBuilder =
    ExternalIdsCompanion Function({
      Value<int> id,
      required int workId,
      required String provider,
      required String providerEntityId,
      Value<DateTime> createdAt,
    });
typedef $$ExternalIdsTableUpdateCompanionBuilder =
    ExternalIdsCompanion Function({
      Value<int> id,
      Value<int> workId,
      Value<String> provider,
      Value<String> providerEntityId,
      Value<DateTime> createdAt,
    });

final class $$ExternalIdsTableReferences
    extends BaseReferences<_$AppDatabase, $ExternalIdsTable, ExternalIdData> {
  $$ExternalIdsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $WorksTable _workIdTable(_$AppDatabase db) =>
      db.works.createAlias('external_ids__work_id__works__id');

  $$WorksTableProcessedTableManager get workId {
    final $_column = $_itemColumn<int>('work_id')!;

    final manager = $$WorksTableTableManager(
      $_db,
      $_db.works,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_workIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ExternalIdsTableFilterComposer
    extends Composer<_$AppDatabase, $ExternalIdsTable> {
  $$ExternalIdsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get providerEntityId => $composableBuilder(
    column: $table.providerEntityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$WorksTableFilterComposer get workId {
    final $$WorksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableFilterComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExternalIdsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExternalIdsTable> {
  $$ExternalIdsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get providerEntityId => $composableBuilder(
    column: $table.providerEntityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorksTableOrderingComposer get workId {
    final $$WorksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableOrderingComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExternalIdsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExternalIdsTable> {
  $$ExternalIdsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get providerEntityId => $composableBuilder(
    column: $table.providerEntityId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$WorksTableAnnotationComposer get workId {
    final $$WorksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.workId,
      referencedTable: $db.works,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorksTableAnnotationComposer(
            $db: $db,
            $table: $db.works,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExternalIdsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExternalIdsTable,
          ExternalIdData,
          $$ExternalIdsTableFilterComposer,
          $$ExternalIdsTableOrderingComposer,
          $$ExternalIdsTableAnnotationComposer,
          $$ExternalIdsTableCreateCompanionBuilder,
          $$ExternalIdsTableUpdateCompanionBuilder,
          (ExternalIdData, $$ExternalIdsTableReferences),
          ExternalIdData,
          PrefetchHooks Function({bool workId})
        > {
  $$ExternalIdsTableTableManager(_$AppDatabase db, $ExternalIdsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExternalIdsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExternalIdsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExternalIdsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> workId = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> providerEntityId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ExternalIdsCompanion(
                id: id,
                workId: workId,
                provider: provider,
                providerEntityId: providerEntityId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int workId,
                required String provider,
                required String providerEntityId,
                Value<DateTime> createdAt = const Value.absent(),
              }) => ExternalIdsCompanion.insert(
                id: id,
                workId: workId,
                provider: provider,
                providerEntityId: providerEntityId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExternalIdsTable, ExternalIdData>(table),
                  $$ExternalIdsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({workId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (workId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.workId,
                        referencedTable: $$ExternalIdsTableReferences
                            ._workIdTable(db),
                        referencedColumn: $$ExternalIdsTableReferences
                            ._workIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ExternalIdsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExternalIdsTable,
      ExternalIdData,
      $$ExternalIdsTableFilterComposer,
      $$ExternalIdsTableOrderingComposer,
      $$ExternalIdsTableAnnotationComposer,
      $$ExternalIdsTableCreateCompanionBuilder,
      $$ExternalIdsTableUpdateCompanionBuilder,
      (ExternalIdData, $$ExternalIdsTableReferences),
      ExternalIdData,
      PrefetchHooks Function({bool workId})
    >;
typedef $$MetadataCachesTableCreateCompanionBuilder =
    MetadataCachesCompanion Function({
      required String cacheKey,
      required String provider,
      required String payloadJson,
      Value<String?> etag,
      required DateTime expiresAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$MetadataCachesTableUpdateCompanionBuilder =
    MetadataCachesCompanion Function({
      Value<String> cacheKey,
      Value<String> provider,
      Value<String> payloadJson,
      Value<String?> etag,
      Value<DateTime> expiresAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$MetadataCachesTableFilterComposer
    extends Composer<_$AppDatabase, $MetadataCachesTable> {
  $$MetadataCachesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MetadataCachesTableOrderingComposer
    extends Composer<_$AppDatabase, $MetadataCachesTable> {
  $$MetadataCachesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MetadataCachesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MetadataCachesTable> {
  $$MetadataCachesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$MetadataCachesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MetadataCachesTable,
          MetadataCacheData,
          $$MetadataCachesTableFilterComposer,
          $$MetadataCachesTableOrderingComposer,
          $$MetadataCachesTableAnnotationComposer,
          $$MetadataCachesTableCreateCompanionBuilder,
          $$MetadataCachesTableUpdateCompanionBuilder,
          (
            MetadataCacheData,
            BaseReferences<
              _$AppDatabase,
              $MetadataCachesTable,
              MetadataCacheData
            >,
          ),
          MetadataCacheData,
          PrefetchHooks Function()
        > {
  $$MetadataCachesTableTableManager(
    _$AppDatabase db,
    $MetadataCachesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetadataCachesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetadataCachesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetadataCachesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cacheKey = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<DateTime> expiresAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetadataCachesCompanion(
                cacheKey: cacheKey,
                provider: provider,
                payloadJson: payloadJson,
                etag: etag,
                expiresAt: expiresAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cacheKey,
                required String provider,
                required String payloadJson,
                Value<String?> etag = const Value.absent(),
                required DateTime expiresAt,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetadataCachesCompanion.insert(
                cacheKey: cacheKey,
                provider: provider,
                payloadJson: payloadJson,
                etag: etag,
                expiresAt: expiresAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MetadataCachesTable, MetadataCacheData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $MetadataCachesTable,
                    MetadataCacheData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MetadataCachesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MetadataCachesTable,
      MetadataCacheData,
      $$MetadataCachesTableFilterComposer,
      $$MetadataCachesTableOrderingComposer,
      $$MetadataCachesTableAnnotationComposer,
      $$MetadataCachesTableCreateCompanionBuilder,
      $$MetadataCachesTableUpdateCompanionBuilder,
      (
        MetadataCacheData,
        BaseReferences<_$AppDatabase, $MetadataCachesTable, MetadataCacheData>,
      ),
      MetadataCacheData,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SyncStateCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SyncStateCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStateTable, SyncStateData>(table),
                  BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;
typedef $$SyncCursorsTableCreateCompanionBuilder =
    SyncCursorsCompanion Function({
      required String deviceId,
      required int lastSequence,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$SyncCursorsTableUpdateCompanionBuilder =
    SyncCursorsCompanion Function({
      Value<String> deviceId,
      Value<int> lastSequence,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$SyncCursorsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSequence => $composableBuilder(
    column: $table.lastSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCursorsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSequence => $composableBuilder(
    column: $table.lastSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCursorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get lastSequence => $composableBuilder(
    column: $table.lastSequence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncCursorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncCursorsTable,
          SyncCursorData,
          $$SyncCursorsTableFilterComposer,
          $$SyncCursorsTableOrderingComposer,
          $$SyncCursorsTableAnnotationComposer,
          $$SyncCursorsTableCreateCompanionBuilder,
          $$SyncCursorsTableUpdateCompanionBuilder,
          (
            SyncCursorData,
            BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursorData>,
          ),
          SyncCursorData,
          PrefetchHooks Function()
        > {
  $$SyncCursorsTableTableManager(_$AppDatabase db, $SyncCursorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> deviceId = const Value.absent(),
                Value<int> lastSequence = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion(
                deviceId: deviceId,
                lastSequence: lastSequence,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                required int lastSequence,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion.insert(
                deviceId: deviceId,
                lastSequence: lastSequence,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncCursorsTable, SyncCursorData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncCursorsTable,
                    SyncCursorData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncCursorsTable,
      SyncCursorData,
      $$SyncCursorsTableFilterComposer,
      $$SyncCursorsTableOrderingComposer,
      $$SyncCursorsTableAnnotationComposer,
      $$SyncCursorsTableCreateCompanionBuilder,
      $$SyncCursorsTableUpdateCompanionBuilder,
      (
        SyncCursorData,
        BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursorData>,
      ),
      SyncCursorData,
      PrefetchHooks Function()
    >;
typedef $$SyncLocalRegistersTableCreateCompanionBuilder =
    SyncLocalRegistersCompanion Function({
      required String recordKey,
      required String kind,
      required String targetId,
      required String targetJson,
      required int versionStamp,
      required String versionDeviceId,
      required String valueJson,
      Value<bool> dirty,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$SyncLocalRegistersTableUpdateCompanionBuilder =
    SyncLocalRegistersCompanion Function({
      Value<String> recordKey,
      Value<String> kind,
      Value<String> targetId,
      Value<String> targetJson,
      Value<int> versionStamp,
      Value<String> versionDeviceId,
      Value<String> valueJson,
      Value<bool> dirty,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$SyncLocalRegistersTableFilterComposer
    extends Composer<_$AppDatabase, $SyncLocalRegistersTable> {
  $$SyncLocalRegistersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get versionStamp => $composableBuilder(
    column: $table.versionStamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionDeviceId => $composableBuilder(
    column: $table.versionDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncLocalRegistersTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncLocalRegistersTable> {
  $$SyncLocalRegistersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get versionStamp => $composableBuilder(
    column: $table.versionStamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionDeviceId => $composableBuilder(
    column: $table.versionDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncLocalRegistersTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncLocalRegistersTable> {
  $$SyncLocalRegistersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordKey =>
      $composableBuilder(column: $table.recordKey, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get versionStamp => $composableBuilder(
    column: $table.versionStamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get versionDeviceId => $composableBuilder(
    column: $table.versionDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncLocalRegistersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncLocalRegistersTable,
          SyncLocalRegisterData,
          $$SyncLocalRegistersTableFilterComposer,
          $$SyncLocalRegistersTableOrderingComposer,
          $$SyncLocalRegistersTableAnnotationComposer,
          $$SyncLocalRegistersTableCreateCompanionBuilder,
          $$SyncLocalRegistersTableUpdateCompanionBuilder,
          (
            SyncLocalRegisterData,
            BaseReferences<
              _$AppDatabase,
              $SyncLocalRegistersTable,
              SyncLocalRegisterData
            >,
          ),
          SyncLocalRegisterData,
          PrefetchHooks Function()
        > {
  $$SyncLocalRegistersTableTableManager(
    _$AppDatabase db,
    $SyncLocalRegistersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncLocalRegistersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncLocalRegistersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncLocalRegistersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> recordKey = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> targetJson = const Value.absent(),
                Value<int> versionStamp = const Value.absent(),
                Value<String> versionDeviceId = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncLocalRegistersCompanion(
                recordKey: recordKey,
                kind: kind,
                targetId: targetId,
                targetJson: targetJson,
                versionStamp: versionStamp,
                versionDeviceId: versionDeviceId,
                valueJson: valueJson,
                dirty: dirty,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recordKey,
                required String kind,
                required String targetId,
                required String targetJson,
                required int versionStamp,
                required String versionDeviceId,
                required String valueJson,
                Value<bool> dirty = const Value.absent(),
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncLocalRegistersCompanion.insert(
                recordKey: recordKey,
                kind: kind,
                targetId: targetId,
                targetJson: targetJson,
                versionStamp: versionStamp,
                versionDeviceId: versionDeviceId,
                valueJson: valueJson,
                dirty: dirty,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncLocalRegistersTable, SyncLocalRegisterData>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncLocalRegistersTable,
                    SyncLocalRegisterData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncLocalRegistersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncLocalRegistersTable,
      SyncLocalRegisterData,
      $$SyncLocalRegistersTableFilterComposer,
      $$SyncLocalRegistersTableOrderingComposer,
      $$SyncLocalRegistersTableAnnotationComposer,
      $$SyncLocalRegistersTableCreateCompanionBuilder,
      $$SyncLocalRegistersTableUpdateCompanionBuilder,
      (
        SyncLocalRegisterData,
        BaseReferences<
          _$AppDatabase,
          $SyncLocalRegistersTable,
          SyncLocalRegisterData
        >,
      ),
      SyncLocalRegisterData,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder = SyncOutboxCompanion Function({
  required int sequence,
  required String recordKey,
  required String kind,
  required String targetJson,
  required int versionStamp,
  required String versionDeviceId,
  required String valueJson,
  required int createdAt,
  Value<int> rowid,
});
typedef $$SyncOutboxTableUpdateCompanionBuilder = SyncOutboxCompanion Function({
  Value<int> sequence,
  Value<String> recordKey,
  Value<String> kind,
  Value<String> targetJson,
  Value<int> versionStamp,
  Value<String> versionDeviceId,
  Value<String> valueJson,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$SyncOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get versionStamp => $composableBuilder(
    column: $table.versionStamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionDeviceId => $composableBuilder(
    column: $table.versionDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get versionStamp => $composableBuilder(
    column: $table.versionStamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionDeviceId => $composableBuilder(
    column: $table.versionDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get recordKey =>
      $composableBuilder(column: $table.recordKey, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get versionStamp => $composableBuilder(
    column: $table.versionStamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get versionDeviceId => $composableBuilder(
    column: $table.versionDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxTable,
          SyncOutboxData,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            SyncOutboxData,
            BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxData>,
          ),
          SyncOutboxData,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$AppDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                Value<String> recordKey = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> targetJson = const Value.absent(),
                Value<int> versionStamp = const Value.absent(),
                Value<String> versionDeviceId = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion(
                sequence: sequence,
                recordKey: recordKey,
                kind: kind,
                targetJson: targetJson,
                versionStamp: versionStamp,
                versionDeviceId: versionDeviceId,
                valueJson: valueJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int sequence,
                required String recordKey,
                required String kind,
                required String targetJson,
                required int versionStamp,
                required String versionDeviceId,
                required String valueJson,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion.insert(
                sequence: sequence,
                recordKey: recordKey,
                kind: kind,
                targetJson: targetJson,
                versionStamp: versionStamp,
                versionDeviceId: versionDeviceId,
                valueJson: valueJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncOutboxTable, SyncOutboxData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncOutboxTable,
                    SyncOutboxData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxTable,
      SyncOutboxData,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        SyncOutboxData,
        BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxData>,
      ),
      SyncOutboxData,
      PrefetchHooks Function()
    >;
typedef $$SyncPendingTableCreateCompanionBuilder =
    SyncPendingCompanion Function({
      required String recordKey,
      required String kind,
      required String targetId,
      required String targetJson,
      required int versionStamp,
      required String versionDeviceId,
      required String valueJson,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$SyncPendingTableUpdateCompanionBuilder =
    SyncPendingCompanion Function({
      Value<String> recordKey,
      Value<String> kind,
      Value<String> targetId,
      Value<String> targetJson,
      Value<int> versionStamp,
      Value<String> versionDeviceId,
      Value<String> valueJson,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$SyncPendingTableFilterComposer
    extends Composer<_$AppDatabase, $SyncPendingTable> {
  $$SyncPendingTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get versionStamp => $composableBuilder(
    column: $table.versionStamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionDeviceId => $composableBuilder(
    column: $table.versionDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncPendingTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncPendingTable> {
  $$SyncPendingTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get versionStamp => $composableBuilder(
    column: $table.versionStamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionDeviceId => $composableBuilder(
    column: $table.versionDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncPendingTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncPendingTable> {
  $$SyncPendingTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordKey =>
      $composableBuilder(column: $table.recordKey, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get targetJson => $composableBuilder(
    column: $table.targetJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get versionStamp => $composableBuilder(
    column: $table.versionStamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get versionDeviceId => $composableBuilder(
    column: $table.versionDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncPendingTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncPendingTable,
          SyncPendingData,
          $$SyncPendingTableFilterComposer,
          $$SyncPendingTableOrderingComposer,
          $$SyncPendingTableAnnotationComposer,
          $$SyncPendingTableCreateCompanionBuilder,
          $$SyncPendingTableUpdateCompanionBuilder,
          (
            SyncPendingData,
            BaseReferences<_$AppDatabase, $SyncPendingTable, SyncPendingData>,
          ),
          SyncPendingData,
          PrefetchHooks Function()
        > {
  $$SyncPendingTableTableManager(_$AppDatabase db, $SyncPendingTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncPendingTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncPendingTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncPendingTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> recordKey = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> targetJson = const Value.absent(),
                Value<int> versionStamp = const Value.absent(),
                Value<String> versionDeviceId = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncPendingCompanion(
                recordKey: recordKey,
                kind: kind,
                targetId: targetId,
                targetJson: targetJson,
                versionStamp: versionStamp,
                versionDeviceId: versionDeviceId,
                valueJson: valueJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recordKey,
                required String kind,
                required String targetId,
                required String targetJson,
                required int versionStamp,
                required String versionDeviceId,
                required String valueJson,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncPendingCompanion.insert(
                recordKey: recordKey,
                kind: kind,
                targetId: targetId,
                targetJson: targetJson,
                versionStamp: versionStamp,
                versionDeviceId: versionDeviceId,
                valueJson: valueJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncPendingTable, SyncPendingData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncPendingTable,
                    SyncPendingData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncPendingTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncPendingTable,
      SyncPendingData,
      $$SyncPendingTableFilterComposer,
      $$SyncPendingTableOrderingComposer,
      $$SyncPendingTableAnnotationComposer,
      $$SyncPendingTableCreateCompanionBuilder,
      $$SyncPendingTableUpdateCompanionBuilder,
      (
        SyncPendingData,
        BaseReferences<_$AppDatabase, $SyncPendingTable, SyncPendingData>,
      ),
      SyncPendingData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MediaSourcesTableTableManager get mediaSources =>
      $$MediaSourcesTableTableManager(_db, _db.mediaSources);
  $$MediaEntriesTableTableManager get mediaEntries =>
      $$MediaEntriesTableTableManager(_db, _db.mediaEntries);
  $$MediaFilesTableTableManager get mediaFiles =>
      $$MediaFilesTableTableManager(_db, _db.mediaFiles);
  $$WorksTableTableManager get works =>
      $$WorksTableTableManager(_db, _db.works);
  $$SeasonsTableTableManager get seasons =>
      $$SeasonsTableTableManager(_db, _db.seasons);
  $$EpisodesTableTableManager get episodes =>
      $$EpisodesTableTableManager(_db, _db.episodes);
  $$MediaAssignmentsTableTableManager get mediaAssignments =>
      $$MediaAssignmentsTableTableManager(_db, _db.mediaAssignments);
  $$PlaybackProgressesTableTableManager get playbackProgresses =>
      $$PlaybackProgressesTableTableManager(_db, _db.playbackProgresses);
  $$ExternalIdsTableTableManager get externalIds =>
      $$ExternalIdsTableTableManager(_db, _db.externalIds);
  $$MetadataCachesTableTableManager get metadataCaches =>
      $$MetadataCachesTableTableManager(_db, _db.metadataCaches);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$SyncCursorsTableTableManager get syncCursors =>
      $$SyncCursorsTableTableManager(_db, _db.syncCursors);
  $$SyncLocalRegistersTableTableManager get syncLocalRegisters =>
      $$SyncLocalRegistersTableTableManager(_db, _db.syncLocalRegisters);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  $$SyncPendingTableTableManager get syncPending =>
      $$SyncPendingTableTableManager(_db, _db.syncPending);
}
