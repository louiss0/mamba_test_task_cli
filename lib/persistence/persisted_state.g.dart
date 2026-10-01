// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'persisted_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PersistedBook _$PersistedBookFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PersistedBook', json, ($checkedConvert) {
      final val = PersistedBook(
        version: $checkedConvert('version', (v) => (v as num).toInt()),
        lists: $checkedConvert(
          'lists',
          (v) => (v as List<dynamic>)
              .map((e) => PersistedList.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$PersistedBookToJson(PersistedBook instance) =>
    <String, dynamic>{'version': instance.version, 'lists': instance.lists};

PersistedList _$PersistedListFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PersistedList', json, ($checkedConvert) {
      final val = PersistedList(
        id: $checkedConvert('id', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        tasks: $checkedConvert(
          'tasks',
          (v) => (v as List<dynamic>)
              .map((e) => PersistedTask.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$PersistedListToJson(PersistedList instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'tasks': instance.tasks,
    };

PersistedTask _$PersistedTaskFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PersistedTask', json, ($checkedConvert) {
      final val = PersistedTask(
        id: $checkedConvert('id', (v) => v as String),
        title: $checkedConvert('title', (v) => v as String),
        completed: $checkedConvert('completed', (v) => v as bool),
        createdAt: $checkedConvert(
          'createdAt',
          (v) => DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$PersistedTaskToJson(PersistedTask instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'completed': instance.completed,
      'createdAt': instance.createdAt.toIso8601String(),
    };
