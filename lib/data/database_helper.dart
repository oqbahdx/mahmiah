import 'dart:io';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mahmiah/main.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
 
 part 'database_helper.g.dart';
// Define adapter
@HiveType(typeId: 1)
class LocationModel extends HiveObject {
  @HiveField(0)
  late String title;
  
  @HiveField(1)
  late String description;
  
  @HiveField(2)
  late double latitude;
  
  @HiveField(3)
  late double longitude;
  
  @HiveField(4)
  String? imagePath;
}

// Initialize Hive (in main())
Future<void> initHive() async {
  final appDocumentDir = await path_provider.getApplicationDocumentsDirectory();
  Hive.init(appDocumentDir.path);
  Hive.registerAdapter(LocationModelAdapter());
  await Hive.openBox<LocationModel>('locations');
}

// Save locations
Future<void> saveLocationsToHive(List<MapLocation> locations) async {
  final box = Hive.box<LocationModel>('locations');
  await box.clear();
  
  for (var location in locations) {
    final locationModel = LocationModel()
      ..title = location.title
      ..description = location.description
      ..latitude = location.position.latitude
      ..longitude = location.position.longitude
      ..imagePath = location.imageFile?.path;
      
    await box.add(locationModel);
  }
}

// Retrieve locations
List<MapLocation> getLocationsFromHive() {
  final box = Hive.box<LocationModel>('locations');
  
  return box.values.map((locationModel) => MapLocation(
    title: locationModel.title,
    description: locationModel.description,
    position: LatLng(locationModel.latitude, locationModel.longitude),
    imageFile: locationModel.imagePath != null ? File(locationModel.imagePath!) : null,
  )).toList();
}