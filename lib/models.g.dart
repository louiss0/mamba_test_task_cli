// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StoredState _$StoredStateFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StoredState', json, ($checkedConvert) {
      $checkKeys(json, allowedKeys: const ['version', 'lists']);
      final val = StoredState(
        version: $checkedConvert('version', (v) => _strictVersion(v)),
        lists: $checkedConvert(
          'lists',
          (v) => (v as List<dynamic>)
              .map((e) => StoredList.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$StoredStateToJson(StoredState instance) =>
    <String, dynamic>{
      'version': instance.version,
      'lists': instance.lists.map((e) => e.toJson()).toList(),
    };

StoredList _$StoredListFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StoredList', json, ($checkedConvert) {
      $checkKeys(json, allowedKeys: const ['id', 'name', 'tasks']);
      final val = StoredList(
        id: $checkedConvert('id', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        tasks: $checkedConvert(
          'tasks',
          (v) => (v as List<dynamic>)
              .map((e) => StoredTask.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
      return val;
    });

Map<String, dynamic> _$StoredListToJson(StoredList instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'tasks': instance.tasks.map((e) => e.toJson()).toList(),
    };

StoredTask _$StoredTaskFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StoredTask', json, ($checkedConvert) {
      $checkKeys(
        json,
        allowedKeys: const ['id', 'title', 'completed', 'createdAt'],
      );
      final val = StoredTask(
        id: $checkedConvert('id', (v) => v as String),
        title: $checkedConvert('title', (v) => v as String),
        completed: $checkedConvert('completed', (v) => v as bool),
        createdAt: $checkedConvert('createdAt', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$StoredTaskToJson(StoredTask instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'completed': instance.completed,
      'createdAt': instance.createdAt,
    };
