import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mahmiah/data/database_helper.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();
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
        fontFamily: 'Poppins',
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
  late GoogleMapController _mapController;
  final Set<Marker> _markers = {};
  LatLng _currentPosition = const LatLng(37.4219999, -122.0840575); // Default position
  bool _isLoading = true;
 
  
  @override
  void initState() {
    super.initState();
    _getUserLocation();
     _loadSavedLocations();
  }
  Future<void> _loadSavedLocations() async {
  setState(() {
    _locations = getLocationsFromHive();
    // Rebuild markers based on loaded locations
    _rebuildMarkers();
  });
}
  Future<void> _getUserLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Request location permissions
      var status = await Permission.location.request();
      if (status.isGranted) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _isLoading = false;
        });
        
        if (_markers.isEmpty) {
          _addMarkerAtCurrentPosition();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required'))
        );
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e'))
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addMarkerAtCurrentPosition() {
    setState(() {
      _markers.add(
        Marker(
          markerId: const MarkerId('current_position'),
          position: _currentPosition,
          infoWindow: const InfoWindow(title: 'Current Location'),
        ),
      );
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
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
  
  // Save to local storage
  saveLocationsToHive(_locations);

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Location note added successfully')),
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
              child: const Icon(Icons.add_location),
            )
          : null,
    );
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: _currentPosition,
                  zoom: 15,
                ),
                zoomControlsEnabled: false,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                markers: _markers,
              ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'DataBand',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),
          ),
        ),
      ],
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
                                      _mapController.animateCamera(
                                        CameraUpdate.newLatLngZoom(
                                          location.position,
                                          17,
                                        ),
                                      );
                                    },
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