// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TelemetryEntriesTable extends TelemetryEntries
    with TableInfo<$TelemetryEntriesTable, TelemetryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TelemetryEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _temperatureMeta = const VerificationMeta(
    'temperature',
  );
  @override
  late final GeneratedColumn<double> temperature = GeneratedColumn<double>(
    'temperature',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isOnMeta = const VerificationMeta('isOn');
  @override
  late final GeneratedColumn<bool> isOn = GeneratedColumn<bool>(
    'is_on',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_on" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _minTempMeta = const VerificationMeta(
    'minTemp',
  );
  @override
  late final GeneratedColumn<int> minTemp = GeneratedColumn<int>(
    'min_temp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(30),
  );
  static const VerificationMeta _maxTempMeta = const VerificationMeta(
    'maxTemp',
  );
  @override
  late final GeneratedColumn<int> maxTemp = GeneratedColumn<int>(
    'max_temp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(60),
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    timestamp,
    temperature,
    isOn,
    minTemp,
    maxTemp,
    synced,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'telemetry_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<TelemetryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('temperature')) {
      context.handle(
        _temperatureMeta,
        temperature.isAcceptableOrUnknown(
          data['temperature']!,
          _temperatureMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_temperatureMeta);
    }
    if (data.containsKey('is_on')) {
      context.handle(
        _isOnMeta,
        isOn.isAcceptableOrUnknown(data['is_on']!, _isOnMeta),
      );
    }
    if (data.containsKey('min_temp')) {
      context.handle(
        _minTempMeta,
        minTemp.isAcceptableOrUnknown(data['min_temp']!, _minTempMeta),
      );
    }
    if (data.containsKey('max_temp')) {
      context.handle(
        _maxTempMeta,
        maxTemp.isAcceptableOrUnknown(data['max_temp']!, _maxTempMeta),
      );
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TelemetryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TelemetryEntry(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      deviceId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}device_id'],
          )!,
      timestamp:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}timestamp'],
          )!,
      temperature:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}temperature'],
          )!,
      isOn:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}is_on'],
          )!,
      minTemp:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}min_temp'],
          )!,
      maxTemp:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}max_temp'],
          )!,
      synced:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}synced'],
          )!,
    );
  }

  @override
  $TelemetryEntriesTable createAlias(String alias) {
    return $TelemetryEntriesTable(attachedDatabase, alias);
  }
}

class TelemetryEntry extends DataClass implements Insertable<TelemetryEntry> {
  /// Auto-increment primary key.
  final int id;

  /// BLE device ID this reading came from.
  final String deviceId;

  /// UTC timestamp of the reading.
  final DateTime timestamp;

  /// Water temperature in °C (stored as real).
  final double temperature;

  /// Whether the relay was closed — mains supplied to the geyser
  /// (0 = off, 1 = on).
  final bool isOn;

  /// Min temp limit at time of reading.
  final int minTemp;

  /// Max temp limit at time of reading.
  final int maxTemp;

  /// Whether this record has been pushed to Firebase.
  final bool synced;
  const TelemetryEntry({
    required this.id,
    required this.deviceId,
    required this.timestamp,
    required this.temperature,
    required this.isOn,
    required this.minTemp,
    required this.maxTemp,
    required this.synced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['temperature'] = Variable<double>(temperature);
    map['is_on'] = Variable<bool>(isOn);
    map['min_temp'] = Variable<int>(minTemp);
    map['max_temp'] = Variable<int>(maxTemp);
    map['synced'] = Variable<bool>(synced);
    return map;
  }

  TelemetryEntriesCompanion toCompanion(bool nullToAbsent) {
    return TelemetryEntriesCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      timestamp: Value(timestamp),
      temperature: Value(temperature),
      isOn: Value(isOn),
      minTemp: Value(minTemp),
      maxTemp: Value(maxTemp),
      synced: Value(synced),
    );
  }

  factory TelemetryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TelemetryEntry(
      id: serializer.fromJson<int>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      temperature: serializer.fromJson<double>(json['temperature']),
      isOn: serializer.fromJson<bool>(json['isOn']),
      minTemp: serializer.fromJson<int>(json['minTemp']),
      maxTemp: serializer.fromJson<int>(json['maxTemp']),
      synced: serializer.fromJson<bool>(json['synced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'temperature': serializer.toJson<double>(temperature),
      'isOn': serializer.toJson<bool>(isOn),
      'minTemp': serializer.toJson<int>(minTemp),
      'maxTemp': serializer.toJson<int>(maxTemp),
      'synced': serializer.toJson<bool>(synced),
    };
  }

  TelemetryEntry copyWith({
    int? id,
    String? deviceId,
    DateTime? timestamp,
    double? temperature,
    bool? isOn,
    int? minTemp,
    int? maxTemp,
    bool? synced,
  }) => TelemetryEntry(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    timestamp: timestamp ?? this.timestamp,
    temperature: temperature ?? this.temperature,
    isOn: isOn ?? this.isOn,
    minTemp: minTemp ?? this.minTemp,
    maxTemp: maxTemp ?? this.maxTemp,
    synced: synced ?? this.synced,
  );
  TelemetryEntry copyWithCompanion(TelemetryEntriesCompanion data) {
    return TelemetryEntry(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      temperature:
          data.temperature.present ? data.temperature.value : this.temperature,
      isOn: data.isOn.present ? data.isOn.value : this.isOn,
      minTemp: data.minTemp.present ? data.minTemp.value : this.minTemp,
      maxTemp: data.maxTemp.present ? data.maxTemp.value : this.maxTemp,
      synced: data.synced.present ? data.synced.value : this.synced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TelemetryEntry(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('timestamp: $timestamp, ')
          ..write('temperature: $temperature, ')
          ..write('isOn: $isOn, ')
          ..write('minTemp: $minTemp, ')
          ..write('maxTemp: $maxTemp, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    deviceId,
    timestamp,
    temperature,
    isOn,
    minTemp,
    maxTemp,
    synced,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TelemetryEntry &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.timestamp == this.timestamp &&
          other.temperature == this.temperature &&
          other.isOn == this.isOn &&
          other.minTemp == this.minTemp &&
          other.maxTemp == this.maxTemp &&
          other.synced == this.synced);
}

class TelemetryEntriesCompanion extends UpdateCompanion<TelemetryEntry> {
  final Value<int> id;
  final Value<String> deviceId;
  final Value<DateTime> timestamp;
  final Value<double> temperature;
  final Value<bool> isOn;
  final Value<int> minTemp;
  final Value<int> maxTemp;
  final Value<bool> synced;
  const TelemetryEntriesCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.temperature = const Value.absent(),
    this.isOn = const Value.absent(),
    this.minTemp = const Value.absent(),
    this.maxTemp = const Value.absent(),
    this.synced = const Value.absent(),
  });
  TelemetryEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String deviceId,
    required DateTime timestamp,
    required double temperature,
    this.isOn = const Value.absent(),
    this.minTemp = const Value.absent(),
    this.maxTemp = const Value.absent(),
    this.synced = const Value.absent(),
  }) : deviceId = Value(deviceId),
       timestamp = Value(timestamp),
       temperature = Value(temperature);
  static Insertable<TelemetryEntry> custom({
    Expression<int>? id,
    Expression<String>? deviceId,
    Expression<DateTime>? timestamp,
    Expression<double>? temperature,
    Expression<bool>? isOn,
    Expression<int>? minTemp,
    Expression<int>? maxTemp,
    Expression<bool>? synced,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (timestamp != null) 'timestamp': timestamp,
      if (temperature != null) 'temperature': temperature,
      if (isOn != null) 'is_on': isOn,
      if (minTemp != null) 'min_temp': minTemp,
      if (maxTemp != null) 'max_temp': maxTemp,
      if (synced != null) 'synced': synced,
    });
  }

  TelemetryEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? deviceId,
    Value<DateTime>? timestamp,
    Value<double>? temperature,
    Value<bool>? isOn,
    Value<int>? minTemp,
    Value<int>? maxTemp,
    Value<bool>? synced,
  }) {
    return TelemetryEntriesCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      timestamp: timestamp ?? this.timestamp,
      temperature: temperature ?? this.temperature,
      isOn: isOn ?? this.isOn,
      minTemp: minTemp ?? this.minTemp,
      maxTemp: maxTemp ?? this.maxTemp,
      synced: synced ?? this.synced,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (temperature.present) {
      map['temperature'] = Variable<double>(temperature.value);
    }
    if (isOn.present) {
      map['is_on'] = Variable<bool>(isOn.value);
    }
    if (minTemp.present) {
      map['min_temp'] = Variable<int>(minTemp.value);
    }
    if (maxTemp.present) {
      map['max_temp'] = Variable<int>(maxTemp.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TelemetryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('timestamp: $timestamp, ')
          ..write('temperature: $temperature, ')
          ..write('isOn: $isOn, ')
          ..write('minTemp: $minTemp, ')
          ..write('maxTemp: $maxTemp, ')
          ..write('synced: $synced')
          ..write(')'))
        .toString();
  }
}

class $NotificationEntriesTable extends NotificationEntries
    with TableInfo<$NotificationEntriesTable, NotificationEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotificationEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<int> type = GeneratedColumn<int>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _temperatureMeta = const VerificationMeta(
    'temperature',
  );
  @override
  late final GeneratedColumn<int> temperature = GeneratedColumn<int>(
    'temperature',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dismissedMeta = const VerificationMeta(
    'dismissed',
  );
  @override
  late final GeneratedColumn<bool> dismissed = GeneratedColumn<bool>(
    'dismissed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dismissed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _readMeta = const VerificationMeta('read');
  @override
  late final GeneratedColumn<bool> read = GeneratedColumn<bool>(
    'read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ble'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    type,
    temperature,
    timestamp,
    dismissed,
    read,
    synced,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notification_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotificationEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('temperature')) {
      context.handle(
        _temperatureMeta,
        temperature.isAcceptableOrUnknown(
          data['temperature']!,
          _temperatureMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_temperatureMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('dismissed')) {
      context.handle(
        _dismissedMeta,
        dismissed.isAcceptableOrUnknown(data['dismissed']!, _dismissedMeta),
      );
    }
    if (data.containsKey('read')) {
      context.handle(
        _readMeta,
        read.isAcceptableOrUnknown(data['read']!, _readMeta),
      );
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NotificationEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationEntry(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      deviceId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}device_id'],
          )!,
      type:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}type'],
          )!,
      temperature:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}temperature'],
          )!,
      timestamp:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}timestamp'],
          )!,
      dismissed:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}dismissed'],
          )!,
      read:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}read'],
          )!,
      synced:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}synced'],
          )!,
      source:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}source'],
          )!,
    );
  }

  @override
  $NotificationEntriesTable createAlias(String alias) {
    return $NotificationEntriesTable(attachedDatabase, alias);
  }
}

class NotificationEntry extends DataClass
    implements Insertable<NotificationEntry> {
  /// Auto-increment primary key.
  final int id;

  /// BLE device ID this event came from.
  final String deviceId;

  /// Event type code (matches [NotificationType.code]).
  final int type;

  /// Temperature in integer °C at the time of event.
  final int temperature;

  /// UTC timestamp of when the event occurred.
  final DateTime timestamp;

  /// Whether the user has dismissed this notification from the UI.
  ///
  /// Distinct from [read]: dismissing removes a row from the list,
  /// reading only means the user has seen it. The bell badge counts
  /// unread-and-undismissed, so neither action alone leaves a count
  /// stranded with nothing on screen to clear it.
  final bool dismissed;

  /// Whether the user has seen this notification in the list.
  ///
  /// Backfills to `true` for pre-existing rows in the v4 migration:
  /// they predate the concept, and defaulting them unread would spike
  /// the badge on upgrade with events the user has long since handled.
  final bool read;

  /// Whether this record has been pushed to cloud storage.
  final bool synced;

  /// Delivery source: 'ble' or 'remote'.
  final String source;
  const NotificationEntry({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.temperature,
    required this.timestamp,
    required this.dismissed,
    required this.read,
    required this.synced,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['type'] = Variable<int>(type);
    map['temperature'] = Variable<int>(temperature);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['dismissed'] = Variable<bool>(dismissed);
    map['read'] = Variable<bool>(read);
    map['synced'] = Variable<bool>(synced);
    map['source'] = Variable<String>(source);
    return map;
  }

  NotificationEntriesCompanion toCompanion(bool nullToAbsent) {
    return NotificationEntriesCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      type: Value(type),
      temperature: Value(temperature),
      timestamp: Value(timestamp),
      dismissed: Value(dismissed),
      read: Value(read),
      synced: Value(synced),
      source: Value(source),
    );
  }

  factory NotificationEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationEntry(
      id: serializer.fromJson<int>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      type: serializer.fromJson<int>(json['type']),
      temperature: serializer.fromJson<int>(json['temperature']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      dismissed: serializer.fromJson<bool>(json['dismissed']),
      read: serializer.fromJson<bool>(json['read']),
      synced: serializer.fromJson<bool>(json['synced']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'type': serializer.toJson<int>(type),
      'temperature': serializer.toJson<int>(temperature),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'dismissed': serializer.toJson<bool>(dismissed),
      'read': serializer.toJson<bool>(read),
      'synced': serializer.toJson<bool>(synced),
      'source': serializer.toJson<String>(source),
    };
  }

  NotificationEntry copyWith({
    int? id,
    String? deviceId,
    int? type,
    int? temperature,
    DateTime? timestamp,
    bool? dismissed,
    bool? read,
    bool? synced,
    String? source,
  }) => NotificationEntry(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    type: type ?? this.type,
    temperature: temperature ?? this.temperature,
    timestamp: timestamp ?? this.timestamp,
    dismissed: dismissed ?? this.dismissed,
    read: read ?? this.read,
    synced: synced ?? this.synced,
    source: source ?? this.source,
  );
  NotificationEntry copyWithCompanion(NotificationEntriesCompanion data) {
    return NotificationEntry(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      type: data.type.present ? data.type.value : this.type,
      temperature:
          data.temperature.present ? data.temperature.value : this.temperature,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      dismissed: data.dismissed.present ? data.dismissed.value : this.dismissed,
      read: data.read.present ? data.read.value : this.read,
      synced: data.synced.present ? data.synced.value : this.synced,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotificationEntry(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('type: $type, ')
          ..write('temperature: $temperature, ')
          ..write('timestamp: $timestamp, ')
          ..write('dismissed: $dismissed, ')
          ..write('read: $read, ')
          ..write('synced: $synced, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    deviceId,
    type,
    temperature,
    timestamp,
    dismissed,
    read,
    synced,
    source,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationEntry &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.type == this.type &&
          other.temperature == this.temperature &&
          other.timestamp == this.timestamp &&
          other.dismissed == this.dismissed &&
          other.read == this.read &&
          other.synced == this.synced &&
          other.source == this.source);
}

class NotificationEntriesCompanion extends UpdateCompanion<NotificationEntry> {
  final Value<int> id;
  final Value<String> deviceId;
  final Value<int> type;
  final Value<int> temperature;
  final Value<DateTime> timestamp;
  final Value<bool> dismissed;
  final Value<bool> read;
  final Value<bool> synced;
  final Value<String> source;
  const NotificationEntriesCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.type = const Value.absent(),
    this.temperature = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.dismissed = const Value.absent(),
    this.read = const Value.absent(),
    this.synced = const Value.absent(),
    this.source = const Value.absent(),
  });
  NotificationEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String deviceId,
    required int type,
    required int temperature,
    required DateTime timestamp,
    this.dismissed = const Value.absent(),
    this.read = const Value.absent(),
    this.synced = const Value.absent(),
    this.source = const Value.absent(),
  }) : deviceId = Value(deviceId),
       type = Value(type),
       temperature = Value(temperature),
       timestamp = Value(timestamp);
  static Insertable<NotificationEntry> custom({
    Expression<int>? id,
    Expression<String>? deviceId,
    Expression<int>? type,
    Expression<int>? temperature,
    Expression<DateTime>? timestamp,
    Expression<bool>? dismissed,
    Expression<bool>? read,
    Expression<bool>? synced,
    Expression<String>? source,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (type != null) 'type': type,
      if (temperature != null) 'temperature': temperature,
      if (timestamp != null) 'timestamp': timestamp,
      if (dismissed != null) 'dismissed': dismissed,
      if (read != null) 'read': read,
      if (synced != null) 'synced': synced,
      if (source != null) 'source': source,
    });
  }

  NotificationEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? deviceId,
    Value<int>? type,
    Value<int>? temperature,
    Value<DateTime>? timestamp,
    Value<bool>? dismissed,
    Value<bool>? read,
    Value<bool>? synced,
    Value<String>? source,
  }) {
    return NotificationEntriesCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      type: type ?? this.type,
      temperature: temperature ?? this.temperature,
      timestamp: timestamp ?? this.timestamp,
      dismissed: dismissed ?? this.dismissed,
      read: read ?? this.read,
      synced: synced ?? this.synced,
      source: source ?? this.source,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(type.value);
    }
    if (temperature.present) {
      map['temperature'] = Variable<int>(temperature.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (dismissed.present) {
      map['dismissed'] = Variable<bool>(dismissed.value);
    }
    if (read.present) {
      map['read'] = Variable<bool>(read.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationEntriesCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('type: $type, ')
          ..write('temperature: $temperature, ')
          ..write('timestamp: $timestamp, ')
          ..write('dismissed: $dismissed, ')
          ..write('read: $read, ')
          ..write('synced: $synced, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TelemetryEntriesTable telemetryEntries = $TelemetryEntriesTable(
    this,
  );
  late final $NotificationEntriesTable notificationEntries =
      $NotificationEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    telemetryEntries,
    notificationEntries,
  ];
}

typedef $$TelemetryEntriesTableCreateCompanionBuilder =
    TelemetryEntriesCompanion Function({
      Value<int> id,
      required String deviceId,
      required DateTime timestamp,
      required double temperature,
      Value<bool> isOn,
      Value<int> minTemp,
      Value<int> maxTemp,
      Value<bool> synced,
    });
typedef $$TelemetryEntriesTableUpdateCompanionBuilder =
    TelemetryEntriesCompanion Function({
      Value<int> id,
      Value<String> deviceId,
      Value<DateTime> timestamp,
      Value<double> temperature,
      Value<bool> isOn,
      Value<int> minTemp,
      Value<int> maxTemp,
      Value<bool> synced,
    });

class $$TelemetryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $TelemetryEntriesTable> {
  $$TelemetryEntriesTableFilterComposer({
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

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOn => $composableBuilder(
    column: $table.isOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minTemp => $composableBuilder(
    column: $table.minTemp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxTemp => $composableBuilder(
    column: $table.maxTemp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TelemetryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $TelemetryEntriesTable> {
  $$TelemetryEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOn => $composableBuilder(
    column: $table.isOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minTemp => $composableBuilder(
    column: $table.minTemp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxTemp => $composableBuilder(
    column: $table.maxTemp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TelemetryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TelemetryEntriesTable> {
  $$TelemetryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isOn =>
      $composableBuilder(column: $table.isOn, builder: (column) => column);

  GeneratedColumn<int> get minTemp =>
      $composableBuilder(column: $table.minTemp, builder: (column) => column);

  GeneratedColumn<int> get maxTemp =>
      $composableBuilder(column: $table.maxTemp, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);
}

class $$TelemetryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TelemetryEntriesTable,
          TelemetryEntry,
          $$TelemetryEntriesTableFilterComposer,
          $$TelemetryEntriesTableOrderingComposer,
          $$TelemetryEntriesTableAnnotationComposer,
          $$TelemetryEntriesTableCreateCompanionBuilder,
          $$TelemetryEntriesTableUpdateCompanionBuilder,
          (
            TelemetryEntry,
            BaseReferences<
              _$AppDatabase,
              $TelemetryEntriesTable,
              TelemetryEntry
            >,
          ),
          TelemetryEntry,
          PrefetchHooks Function()
        > {
  $$TelemetryEntriesTableTableManager(
    _$AppDatabase db,
    $TelemetryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  $$TelemetryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$TelemetryEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$TelemetryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<double> temperature = const Value.absent(),
                Value<bool> isOn = const Value.absent(),
                Value<int> minTemp = const Value.absent(),
                Value<int> maxTemp = const Value.absent(),
                Value<bool> synced = const Value.absent(),
              }) => TelemetryEntriesCompanion(
                id: id,
                deviceId: deviceId,
                timestamp: timestamp,
                temperature: temperature,
                isOn: isOn,
                minTemp: minTemp,
                maxTemp: maxTemp,
                synced: synced,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String deviceId,
                required DateTime timestamp,
                required double temperature,
                Value<bool> isOn = const Value.absent(),
                Value<int> minTemp = const Value.absent(),
                Value<int> maxTemp = const Value.absent(),
                Value<bool> synced = const Value.absent(),
              }) => TelemetryEntriesCompanion.insert(
                id: id,
                deviceId: deviceId,
                timestamp: timestamp,
                temperature: temperature,
                isOn: isOn,
                minTemp: minTemp,
                maxTemp: maxTemp,
                synced: synced,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TelemetryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TelemetryEntriesTable,
      TelemetryEntry,
      $$TelemetryEntriesTableFilterComposer,
      $$TelemetryEntriesTableOrderingComposer,
      $$TelemetryEntriesTableAnnotationComposer,
      $$TelemetryEntriesTableCreateCompanionBuilder,
      $$TelemetryEntriesTableUpdateCompanionBuilder,
      (
        TelemetryEntry,
        BaseReferences<_$AppDatabase, $TelemetryEntriesTable, TelemetryEntry>,
      ),
      TelemetryEntry,
      PrefetchHooks Function()
    >;
typedef $$NotificationEntriesTableCreateCompanionBuilder =
    NotificationEntriesCompanion Function({
      Value<int> id,
      required String deviceId,
      required int type,
      required int temperature,
      required DateTime timestamp,
      Value<bool> dismissed,
      Value<bool> read,
      Value<bool> synced,
      Value<String> source,
    });
typedef $$NotificationEntriesTableUpdateCompanionBuilder =
    NotificationEntriesCompanion Function({
      Value<int> id,
      Value<String> deviceId,
      Value<int> type,
      Value<int> temperature,
      Value<DateTime> timestamp,
      Value<bool> dismissed,
      Value<bool> read,
      Value<bool> synced,
      Value<String> source,
    });

class $$NotificationEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $NotificationEntriesTable> {
  $$NotificationEntriesTableFilterComposer({
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

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dismissed => $composableBuilder(
    column: $table.dismissed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotificationEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotificationEntriesTable> {
  $$NotificationEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dismissed => $composableBuilder(
    column: $table.dismissed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotificationEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotificationEntriesTable> {
  $$NotificationEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<bool> get dismissed =>
      $composableBuilder(column: $table.dismissed, builder: (column) => column);

  GeneratedColumn<bool> get read =>
      $composableBuilder(column: $table.read, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$NotificationEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotificationEntriesTable,
          NotificationEntry,
          $$NotificationEntriesTableFilterComposer,
          $$NotificationEntriesTableOrderingComposer,
          $$NotificationEntriesTableAnnotationComposer,
          $$NotificationEntriesTableCreateCompanionBuilder,
          $$NotificationEntriesTableUpdateCompanionBuilder,
          (
            NotificationEntry,
            BaseReferences<
              _$AppDatabase,
              $NotificationEntriesTable,
              NotificationEntry
            >,
          ),
          NotificationEntry,
          PrefetchHooks Function()
        > {
  $$NotificationEntriesTableTableManager(
    _$AppDatabase db,
    $NotificationEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$NotificationEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$NotificationEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$NotificationEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> type = const Value.absent(),
                Value<int> temperature = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<bool> dismissed = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<String> source = const Value.absent(),
              }) => NotificationEntriesCompanion(
                id: id,
                deviceId: deviceId,
                type: type,
                temperature: temperature,
                timestamp: timestamp,
                dismissed: dismissed,
                read: read,
                synced: synced,
                source: source,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String deviceId,
                required int type,
                required int temperature,
                required DateTime timestamp,
                Value<bool> dismissed = const Value.absent(),
                Value<bool> read = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<String> source = const Value.absent(),
              }) => NotificationEntriesCompanion.insert(
                id: id,
                deviceId: deviceId,
                type: type,
                temperature: temperature,
                timestamp: timestamp,
                dismissed: dismissed,
                read: read,
                synced: synced,
                source: source,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotificationEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotificationEntriesTable,
      NotificationEntry,
      $$NotificationEntriesTableFilterComposer,
      $$NotificationEntriesTableOrderingComposer,
      $$NotificationEntriesTableAnnotationComposer,
      $$NotificationEntriesTableCreateCompanionBuilder,
      $$NotificationEntriesTableUpdateCompanionBuilder,
      (
        NotificationEntry,
        BaseReferences<
          _$AppDatabase,
          $NotificationEntriesTable,
          NotificationEntry
        >,
      ),
      NotificationEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TelemetryEntriesTableTableManager get telemetryEntries =>
      $$TelemetryEntriesTableTableManager(_db, _db.telemetryEntries);
  $$NotificationEntriesTableTableManager get notificationEntries =>
      $$NotificationEntriesTableTableManager(_db, _db.notificationEntries);
}
