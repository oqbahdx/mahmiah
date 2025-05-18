import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mahmiah/data/database_helper.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();
  await FMTCObjectBoxBackend().initialise();
  final store = FMTCStore('offlineMap');
  await store.manage.create();
  runApp(const MapNotesApp());
}

class MapNotesApp extends StatelessWidget {
  const MapNotesApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Data Band',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Poppins',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class MapLocation {
  final String title;
  final String description;
  final LatLng position;
  final File? imageFile;

  MapLocation({
    required this.title,
    required this.description,
    required this.position,
    this.imageFile,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<MapLocation> _locations = [];
  int _currentIndex = 0;
  MapController _mapController = MapController();
  final List<Marker> _markers = [];
  LatLng _currentPosition = LatLng(37.4219999, -122.0840575);
  bool _isLoading = true;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _locationSaveTimer;
  bool _autoSaveEnabled = false;
  bool _isOfflineMode = false;
  late FMTCTileProvider _tileProvider;

  @override
  void initState() {
    super.initState();
    _updateTileProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestLocationPermission();
      _loadSavedLocations();
    });
  }
  
  @override
  void dispose() {
    _locationSubscription?.cancel();
    _locationSaveTimer?.cancel();
    super.dispose();
  }

  void _updateTileProvider() {
    _tileProvider = FMTCTileProvider(
      stores: {'offlineMap': BrowseStoreStrategy.readUpdateCreate},
      loadingStrategy: _isOfflineMode ? BrowseLoadingStrategy.cacheOnly : BrowseLoadingStrategy.cacheFirst,
    );
  }

  Future<void> _requestLocationPermission() async {
    var status = await Permission.location.request();
    if (status.isGranted) {
      _startLocationTracking();
    } else {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission is required'))
      );
    }
  }

  void _startLocationTracking() {
    setState(() {
      _isLoading = false;
    });
    
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    
    _locationSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
      .listen((Position position) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _rebuildMarkers();
        });
        
        if (_isLoading) {
          _mapController.move(_currentPosition, 15);
          setState(() {
            _isLoading = false;
          });
        }
      }, onError: (e) {
        print("Error getting location: $e");
        setState(() {
          _isLoading = false;
        });
      });
  }

  void _toggleAutoSave() {
    setState(() {
      _autoSaveEnabled = !_autoSaveEnabled;
    });
    
    if (_autoSaveEnabled) {
      _startAutoSave();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto-save location enabled - Saving every 2 minutes'))
      );
    } else {
      _locationSaveTimer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto-save location disabled'))
      );
    }
  }
  
  void _startAutoSave() {
    _locationSaveTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _autoSaveLocation();
    });
  }
  
  void _autoSaveLocation() {
    final timestamp = DateTime.now();
    final newLocation = MapLocation(
      title: 'Auto-saved at ${timestamp.hour}:${timestamp.minute}',
      description: 'Automatically saved location on ${timestamp.day}/${timestamp.month}/${timestamp.year}',
      position: _currentPosition,
      imageFile: null,
    );

    setState(() {
      _locations.add(newLocation);
      _addMarkerForLocation(newLocation, _locations.length - 1);
    });
    
    saveLocationsToHive(_locations);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Location auto-saved'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _loadSavedLocations() async {
    setState(() {
      _locations = getLocationsFromHive();
      _rebuildMarkers();
    });
  }

  void _rebuildMarkers() {
    setState(() {
      _markers.clear();
      
      _markers.add(
        Marker(
          point: _currentPosition,
          width: 80,
          height: 80,
          child: const Icon(
            Icons.my_location,
            color: Colors.blue,
            size: 30,
          ),
        ),
      );
      
      for (int i = 0; i < _locations.length; i++) {
        _addMarkerForLocation(_locations[i], i);
      }
    });
  }

  void _addMarkerForLocation(MapLocation location, int index) {
    setState(() {
      _markers.add(
        Marker(
          point: location.position,
          width: 80,
          height: 80,
          child: GestureDetector(
            onTap: () {
              _showLocationDetails(location);
            },
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    location.title,
                    style: const TextStyle(fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  void _showLocationDetails(MapLocation location) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (location.imageFile != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    location.imageFile!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                location.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(location.description),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddNoteDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    File? selectedImage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add New Location Note',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: titleController,
                              decoration: InputDecoration(
                                labelText: 'Title',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: descriptionController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Description',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildImageButton(
                                  icon: Icons.camera_alt,
                                  label: 'Camera',
                                  onPressed: () async {
                                    final image = await ImagePicker().pickImage(
                                      source: ImageSource.camera,
                                    );
                                    if (image != null) {
                                      setState(() {
                                        selectedImage = File(image.path);
                                      });
                                    }
                                  },
                                ),
                                _buildImageButton(
                                  icon: Icons.photo_library,
                                  label: 'Gallery',
                                  onPressed: () async {
                                    final image = await ImagePicker().pickImage(
                                      source: ImageSource.gallery,
                                    );
                                    if (image != null) {
                                      setState(() {
                                        selectedImage = File(image.path);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            selectedImage != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      selectedImage!,
                                      height: 120,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Container(
                                    height: 120,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: const Center(
                                      child: Text('No image selected'),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            if (titleController.text.isNotEmpty && descriptionController.text.isNotEmpty) {
                              _addNewLocation(
                                titleController.text,
                                descriptionController.text,
                                selectedImage,
                              );
                              Navigator.pop(context);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please fill all required fields')),
                              );
                            }
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _addNewLocation(String title, String description, File? imageFile) {
    final newLocation = MapLocation(
      title: title,
      description: description,
      position: _currentPosition,
      imageFile: imageFile,
    );

    setState(() {
      _locations.add(newLocation);
      _addMarkerForLocation(newLocation, _locations.length - 1);
    });
    
    saveLocationsToHive(_locations);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Location note added successfully')),
    );
  }

  void _toggleOfflineMode() {
    setState(() {
      _isOfflineMode = !_isOfflineMode;
      _updateTileProvider();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isOfflineMode ? 'Offline mode enabled - Using cached tiles only' : 'Online mode enabled'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildMapView(),
          _buildSavedLocationsView(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.list),
            label: 'Saved Locations',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _showAddNoteDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildMapView() {
    return StreamBuilder<Position>(
      stream: Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _currentPosition = LatLng(
            snapshot.data!.latitude,
            snapshot.data!.longitude,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _rebuildMarkers();
          });
        }
        
        return Stack(
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialZoom: 15.0,
                      initialCenter: _currentPosition,
                      minZoom: 4.0,
                      maxZoom: 18.0,
                      onTap: (_, point) {
                        setState(() {
                          _currentPosition = point;
                          _rebuildMarkers();
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        tileProvider: _tileProvider,
                        userAgentPackageName: 'com.example.mahmiah',
                      ),
                      MarkerLayer(markers: _markers),
                    ],
                  ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DataBand',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            if (snapshot.hasData)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  'Lat: ${_currentPosition.latitude.toStringAsFixed(5)}, Lng: ${_currentPosition.longitude.toStringAsFixed(5)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.my_location),
                              onPressed: () {
                                if (snapshot.hasData) {
                                  _mapController.move(_currentPosition, 17);
                                }
                              },
                              tooltip: 'Center on current location',
                            ),
                            IconButton(
                              icon: const Icon(Icons.zoom_in),
                              onPressed: () {
                                final zoom = _mapController.camera.zoom + 1;
                                _mapController.move(_mapController.camera.center, zoom > 18 ? 18 : zoom);
                              },
                              tooltip: 'Zoom in',
                            ),
                            IconButton(
                              icon: const Icon(Icons.zoom_out),
                              onPressed: () {
                                final zoom = _mapController.camera.zoom - 1;
                                _mapController.move(_mapController.camera.center, zoom < 4 ? 4 : zoom);
                              },
                              tooltip: 'Zoom out',
                            ),
                            IconButton(
                              icon: Icon(
                                _autoSaveEnabled ? Icons.timer : Icons.timer_off,
                                color: _autoSaveEnabled ? Colors.green : null,
                              ),
                              onPressed: _toggleAutoSave,
                              tooltip: _autoSaveEnabled ? 'Disable auto-save' : 'Enable auto-save',
                            ),
                            IconButton(
                              icon: Icon(
                                _isOfflineMode ? Icons.cloud_off : Icons.cloud,
                                color: _isOfflineMode ? Colors.red : null,
                              ),
                              onPressed: _toggleOfflineMode,
                              tooltip: _isOfflineMode ? 'Switch to online mode' : 'Switch to offline mode',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        snapshot.hasData ? Icons.gps_fixed : Icons.gps_not_fixed,
                        color: snapshot.hasData ? Colors.green : Colors.orange,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        snapshot.hasData 
                            ? 'Live location tracking active'
                            : snapshot.hasError
                                ? 'Location error: ${snapshot.error}'
                                : 'Waiting for location...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSavedLocationsView() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('Saved Locations'),
          floating: true,
          pinned: true,
          snap: false,
          expandedHeight: 120,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 70),
                  child: Text(
                    '${_locations.length} Locations Saved',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _locations.isEmpty
            ? const SliverFillRemaining(
                child: Center(
                  child: Text('No saved locations yet'),
                ),
              )
            : SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final location = _locations[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (location.imageFile != null)
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                                child: Image.file(
                                  location.imageFile!,
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    location.title,
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(location.description),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${location.position.latitude.toStringAsFixed(4)}, ${location.position.longitude.toStringAsFixed(4)}',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 16.0,
                                bottom: 16.0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.map),
                                    label: const Text('View on Map'),
                                    onPressed: () {
                                      setState(() {
                                        _currentIndex = 0;
                                      });
                                      _mapController.move(
                                        location.position,
                                        17,
                                      );
                                    },
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.delete),
                                    label: const Text('Delete'),
                                    onPressed: () {
                                      setState(() {
                                        _locations.removeAt(index);
                                        saveLocationsToHive(_locations);
                                        _rebuildMarkers();
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Location deleted')),
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _locations.length,
                ),
              ),
      ],
    );
  }
}