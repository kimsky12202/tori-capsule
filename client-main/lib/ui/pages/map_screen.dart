import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:image_picker/image_picker.dart' as img_picker;
import 'package:exif/exif.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;

class CapsulePin {
  final String id;
  final double lat;
  final double lng;
  final File? photo;
  final String title;

  CapsulePin({
    required this.id,
    required this.lat,
    required this.lng,
    this.photo,
    required this.title,
  });
}

// ignore: deprecated_member_use
class _AnnotationTapListener implements OnPointAnnotationClickListener {
  final void Function(PointAnnotation) onTap;
  _AnnotationTapListener(this.onTap);

  @override
  void onPointAnnotationClick(PointAnnotation annotation) => onTap(annotation);
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen>
    with AutomaticKeepAliveClientMixin {
  static const String _token = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

  MapboxMap? _map;
  PointAnnotationManager? _pinManager;
  PointAnnotationManager? _myLocManager;
  PointAnnotation? _myLocMarker;

  final List<CapsulePin> _pins = [];
  final Map<String, String> _markerMap = {};
  final img_picker.ImagePicker _picker = img_picker.ImagePicker();
  StreamSubscription<geo.Position>? _posSub;

  bool _isLoading = false;
  bool _tapListenerRegistered = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(_token);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    map.gestures.updateSettings(
      GesturesSettings(
        rotateEnabled: true,
        pinchToZoomEnabled: true,
        scrollEnabled: true,
        doubleTapToZoomInEnabled: true,
        doubleTouchToZoomOutEnabled: true,
        quickZoomEnabled: true,
      ),
    );
    await _moveToMyLocation();
    _startTracking();
  }

  Future<void> _moveToMyLocation() async {
    try {
      geo.LocationPermission perm = await geo.Geolocator.checkPermission();
      if (perm == geo.LocationPermission.denied) {
        perm = await geo.Geolocator.requestPermission();
      }
      final pos = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );
      _map?.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(pos.longitude, pos.latitude)),
          zoom: 14.0,
        ),
        MapAnimationOptions(duration: 1000),
      );
      await _updateMyDot(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('위치 오류: $e');
    }
  }

  Future<void> _updateMyDot(double lat, double lng) async {
    _myLocManager ??= await _map?.annotations.createPointAnnotationManager();
    if (_myLocMarker != null) {
      await _myLocManager?.delete(_myLocMarker!);
      _myLocMarker = null;
    }
    _myLocMarker = await _myLocManager?.create(
      PointAnnotationOptions(
        geometry: Point(coordinates: Position(lng, lat)),
        image: await _makeDotImage(),
        iconSize: 1.0,
      ),
    );
  }

  Future<Uint8List> _makeDotImage() async {
    final rec = PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, 40, 40));
    c.drawCircle(const Offset(20, 20), 18, Paint()..color = const Color(0xFFFFFFFF));
    c.drawCircle(const Offset(20, 20), 13, Paint()..color = const Color(0xFF4A90E2));
    final img = await rec.endRecording().toImage(40, 40);
    final d = await img.toByteData(format: ImageByteFormat.png);
    return d!.buffer.asUint8List();
  }

  void _startTracking() {
    _posSub = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((p) => _updateMyDot(p.latitude, p.longitude));
  }

  Future<geo.Position?> _extractGpsFromPhoto(File photo) async {
    try {
      final bytes = await photo.readAsBytes();
      final data = await readExifFromBytes(bytes);
      if (!data.containsKey('GPS GPSLatitude') ||
          !data.containsKey('GPS GPSLongitude')) {
        return null;
      }
      double? parseDMS(IfdTag tag) {
        final vals = tag.values.toList();
        if (vals.length < 3) return null;
        final r = _r2d(vals[0]) + _r2d(vals[1]) / 60.0 + _r2d(vals[2]) / 3600.0;
        if (r.isNaN || r.isInfinite || r == 0.0) return null;
        return r;
      }

      double? lat = parseDMS(data['GPS GPSLatitude']!);
      double? lng = parseDMS(data['GPS GPSLongitude']!);
      if (lat == null || lng == null) return null;
      if (data['GPS GPSLatitudeRef']?.printable == 'S') lat = -lat;
      if (data['GPS GPSLongitudeRef']?.printable == 'W') lng = -lng;
      return geo.Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    } catch (e) {
      debugPrint('EXIF 오류: $e');
      return null;
    }
  }

  double _r2d(dynamic val) {
    try {
      if (val is num) {
        final d = val.toDouble();
        return (d.isNaN || d.isInfinite) ? 0.0 : d;
      }
      final s = val.toString().trim();
      if (s.contains('/')) {
        final p = s.split('/');
        final n = double.tryParse(p[0]) ?? 0.0;
        final d = double.tryParse(p[1]) ?? 1.0;
        if (d == 0.0) return 0.0;
        final r = n / d;
        return (r.isNaN || r.isInfinite) ? 0.0 : r;
      }
      return double.tryParse(s) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  Future<Uint8List> _makePhotoMarker(File photo) async {
    final image = await decodeImageFromList(await photo.readAsBytes());
    const double sz = 140, pad = 10;
    final rec = PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, sz, sz + 20));
    final tail = Path()
      ..moveTo(sz / 2 - 10, sz - 4)
      ..lineTo(sz / 2, sz + 20)
      ..lineTo(sz / 2 + 10, sz - 4)
      ..close();
    c.drawPath(tail, Paint()..color = const Color(0xFF7B5EA7));
    c.drawCircle(Offset(sz / 2, sz / 2), sz / 2 - 2, Paint()..color = const Color(0xFF7B5EA7));
    c.clipPath(Path()..addOval(
      Rect.fromCircle(center: Offset(sz / 2, sz / 2), radius: sz / 2 - pad),
    ));
    final sw = image.width.toDouble(), sh = image.height.toDouble();
    final ms = math.min(sw, sh);
    c.drawImageRect(
      image,
      Rect.fromCenter(center: Offset(sw / 2, sh / 2), width: ms, height: ms),
      Rect.fromLTWH(pad, pad, sz - pad * 2, sz - pad * 2),
      Paint(),
    );
    final out = await rec.endRecording().toImage(sz.toInt(), (sz + 20).toInt());
    final d = await out.toByteData(format: ImageByteFormat.png);
    return d!.buffer.asUint8List();
  }

  void _registerTapListener() {
    if (_tapListenerRegistered || _pinManager == null) return;
    // ignore: deprecated_member_use
    _pinManager!.addOnPointAnnotationClickListener(
      _AnnotationTapListener((PointAnnotation tapped) {
        final pinId = _markerMap.entries
            .firstWhere(
              (e) => e.value == tapped.id,
              orElse: () => const MapEntry('', ''),
            )
            .key;
        if (pinId.isEmpty) return;
        final p = _pins.firstWhere(
          (p) => p.id == pinId,
          orElse: () => CapsulePin(id: '', lat: 0, lng: 0, title: ''),
        );
        if (p.id.isNotEmpty) _showPinSheet(p);
      }),
    );
    _tapListenerRegistered = true;
  }

  Future<void> addPhotoPin() async {
    final picked = await _picker.pickImage(source: img_picker.ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);
    setState(() => _isLoading = true);
    try {
      geo.Position? gpsPos = await _extractGpsFromPhoto(file);
      if (gpsPos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📍 사진에 GPS 정보가 없어 현재 위치를 사용해요'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        gpsPos = await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
          ),
        );
      }

      final pin = CapsulePin(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        lat: gpsPos.latitude,
        lng: gpsPos.longitude,
        photo: file,
        title: '타임캡슐 ${_pins.length + 1}',
      );
      _pins.add(pin);

      _pinManager ??= await _map?.annotations.createPointAnnotationManager();
      final markerImg = await _makePhotoMarker(file);
      final marker = await _pinManager?.create(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(gpsPos.longitude, gpsPos.latitude)),
          image: markerImg,
          iconSize: 0.8,
        ),
      );
      if (marker != null) _markerMap[pin.id] = marker.id;
      _registerTapListener();

      // 사진 핀 위치로 카메라 이동
      _map?.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(gpsPos.longitude, gpsPos.latitude)),
          zoom: 14.0,
        ),
        MapAnimationOptions(duration: 800),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPinSheet(CapsulePin pin) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (pin.photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  pin.photo!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              pin.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '📍 ${pin.lat.toStringAsFixed(5)}, ${pin.lng.toStringAsFixed(5)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey('capsule_map'),
            styleUri: MapboxStyles.STANDARD,
            cameraOptions: CameraOptions(
              center: Point(coordinates: Position(127.2890, 36.4800)),
              zoom: 6.0,
            ),
            onMapCreated: _onMapCreated,
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF7B5EA7)),
              ),
            ),
          Positioned(
            bottom: 100,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'photo',
              backgroundColor: const Color(0xFF7B5EA7),
              onPressed: addPhotoPin,
              child: const Icon(Icons.add_photo_alternate, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 30,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'location',
              backgroundColor: Colors.white,
              onPressed: _moveToMyLocation,
              child: const Icon(Icons.my_location, color: Color(0xFF7B5EA7)),
            ),
          ),
        ],
      ),
    );
  }
}
