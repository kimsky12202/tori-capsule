import 'package:flutter/material.dart';
import 'package:flutter_unity_widget/flutter_unity_widget.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:image_picker/image_picker.dart' as img_picker;
import 'package:exif/exif.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;

// ── 데이터 모델 (기존 CapsulePin과 동일) ──────────────────────────
class CapsulePin {
  final String id;
  final double lat;
  final double lng;
  final String? photoPath;
  final String title;

  CapsulePin({
    required this.id,
    required this.lat,
    required this.lng,
    this.photoPath,
    required this.title,
  });

  File? get photo => photoPath != null ? File(photoPath!) : null;

  Map<String, dynamic> toJson() => {
    'id': id, 'lat': lat, 'lng': lng, 'photoPath': photoPath, 'title': title,
  };

  factory CapsulePin.fromJson(Map<String, dynamic> j) => CapsulePin(
    id: j['id'] as String,
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    photoPath: j['photoPath'] as String?,
    title: j['title'] as String,
  );
}

// ── Unity 맵 메인 화면 ────────────────────────────────────────────
class UnityMapScreen extends StatefulWidget {
  const UnityMapScreen({super.key});

  @override
  State<UnityMapScreen> createState() => UnityMapScreenState();
}

class UnityMapScreenState extends State<UnityMapScreen>
    with AutomaticKeepAliveClientMixin {
  static const String _prefsKey     = 'capsule_pins';
  static const String _polygonsKey  = 'capsule_polygons';

  UnityWidgetController? _unity;
  bool _unityReady = false;

  final List<CapsulePin> _pins = [];
  final Map<String, List<List<double>>> _buildingPolygons = {};
  final img_picker.ImagePicker _picker = img_picker.ImagePicker();
  StreamSubscription<geo.Position>? _posSub;
  bool _isLoading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _posSub?.cancel();
    _unity?.dispose();
    super.dispose();
  }

  // ── Unity 초기화 완료 콜백 ───────────────────────────────────────
  void _onUnityCreated(UnityWidgetController controller) {
    _unity = controller;
  }

  // Unity 씬 로드 완료 → 초기 데이터 전송
  void _onUnitySceneLoaded(SceneLoaded? scene) async {
    if (scene == null) return;
    setState(() => _unityReady = true);

    // 현재 위치로 카메라 이동
    await _moveToMyLocation();
    _startTracking();
    // 저장된 핀 & 폴리곤 로드 후 Unity에 전송
    await _loadAndSendPins();
  }

  // Unity → Flutter 메시지 수신 (핀 탭, 카메라 이동 요청 등)
  void _onUnityMessage(message) {
    try {
      final data = jsonDecode(message.toString()) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'pinTapped') {
        final pinId = data['id'] as String;
        final pin = _pins.firstWhere(
          (p) => p.id == pinId,
          orElse: () => CapsulePin(id: '', lat: 0, lng: 0, title: ''),
        );
        if (pin.id.isNotEmpty) _showPinSheet(pin);
      }
    } catch (_) {}
  }

  // ── Flutter → Unity 메시지 전송 헬퍼 ────────────────────────────
  void _sendToUnity(String method, Map<String, dynamic> data) {
    if (_unity == null || !_unityReady) return;
    _unity!.postMessage('ToriCapsuleMap', method, jsonEncode(data));
  }

  // ── 위치 이동 ────────────────────────────────────────────────────
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
      _sendToUnity('MoveCamera', {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'zoom': 14.0,
        'pitch': 45.0,
      });
      _sendToUnity('UpdateMyLocation', {
        'lat': pos.latitude,
        'lng': pos.longitude,
      });
    } catch (e) {
      debugPrint('위치 오류: $e');
    }
  }

  void _startTracking() {
    _posSub = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((p) {
      _sendToUnity('UpdateMyLocation', {
        'lat': p.latitude,
        'lng': p.longitude,
      });
    });
  }

  // ── 핀 저장/불러오기 ─────────────────────────────────────────────
  Future<void> _savePins() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      _pins.map((p) => jsonEncode(p.toJson())).toList(),
    );
  }

  Future<void> _savePolygons() async {
    final prefs = await SharedPreferences.getInstance();
    final map = _buildingPolygons.map(
      (id, coords) => MapEntry(id, jsonEncode(coords)),
    );
    await prefs.setString(_polygonsKey, jsonEncode(map));
  }

  Future<void> _loadPolygons() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_polygonsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        final coords = (jsonDecode(e.value as String) as List)
            .map((c) => (c as List).map((v) => (v as num).toDouble()).toList())
            .toList();
        _buildingPolygons[e.key] = coords;
      }
    } catch (_) {}
  }

  Future<void> _loadAndSendPins() async {
    final prefs = await SharedPreferences.getInstance();
    await _loadPolygons();
    final list = prefs.getStringList(_prefsKey) ?? [];

    for (final raw in list) {
      try {
        final pin = CapsulePin.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (pin.photoPath == null || File(pin.photoPath!).existsSync()) {
          _pins.add(pin);
          _sendPinToUnity(pin);

          if (!_buildingPolygons.containsKey(pin.id)) {
            await Future.delayed(const Duration(seconds: 2));
            await _queryBuildingForPin(pin);
            await _savePolygons();
          }
        }
      } catch (_) {}
    }
    _sendFogToUnity();
  }

  // Unity에 핀 전송
  void _sendPinToUnity(CapsulePin pin) {
    _sendToUnity('AddPin', {
      'id': pin.id,
      'lat': pin.lat,
      'lng': pin.lng,
      'title': pin.title,
      'photoPath': pin.photoPath ?? '',
    });
  }

  // 안개 오버레이 GeoJSON을 Unity에 전송
  void _sendFogToUnity() {
    final geoJson = _buildFogGeoJson();
    _sendToUnity('UpdateFog', {'geojson': jsonEncode(geoJson)});
  }

  // ── GeoJSON 안개: 전세계(CCW) + 핀 폴리곤 구멍(CW) ──────────────
  Map<String, dynamic> _buildFogGeoJson() {
    final rings = <List<List<double>>>[
      [[-180.0,-85.0],[180.0,-85.0],[180.0,85.0],[-180.0,85.0],[-180.0,-85.0]],
    ];
    for (final polygon in _buildingPolygons.values) {
      if (polygon.length >= 3) rings.add(_toClockwise(polygon));
    }
    return {
      'type': 'Feature',
      'geometry': {'type': 'Polygon', 'coordinates': rings},
    };
  }

  List<List<double>> _toClockwise(List<List<double>> ring) {
    double area = 0;
    for (int i = 0; i < ring.length - 1; i++) {
      area += ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1];
    }
    return area > 0 ? ring.reversed.toList() : ring;
  }

  // ── OSM Overpass 폴리곤 쿼리 (기존과 동일) ──────────────────────
  Future<void> _queryBuildingForPin(CapsulePin pin) async {
    final lat = pin.lat, lng = pin.lng;

    Future<Map<String, dynamic>?> overpassGet(String q) async {
      final url = Uri.parse(
        'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(q)}',
      );
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          final res = await http.get(url).timeout(const Duration(seconds: 15));
          if (res.statusCode == 200) {
            return jsonDecode(res.body) as Map<String, dynamic>;
          }
          if (res.statusCode == 429) {
            await Future.delayed(Duration(seconds: attempt * 5));
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
      return null;
    }

    try {
      final areaQ =
          '[out:json];is_in($lat,$lng)->.a;('
          'way["tourism"](pivot.a);way["leisure"="park"](pivot.a);'
          'way["leisure"="nature_reserve"](pivot.a);way["historic"](pivot.a);'
          'way["amenity"="university"](pivot.a);'
          'way["landuse"="residential"](pivot.a);'
          'relation["tourism"](pivot.a);relation["leisure"="park"](pivot.a);'
          ');out geom;';
      final areaBody = await overpassGet(areaQ);
      if (areaBody != null) {
        final polygon = _extractPolygon(areaBody);
        if (polygon != null) {
          _buildingPolygons[pin.id] = polygon;
          return;
        }
      }

      final buildingQ =
          '[out:json];way["building"](around:50,$lat,$lng);out geom;';
      final buildingBody = await overpassGet(buildingQ);
      if (buildingBody != null) {
        final polygon = _extractPolygon(buildingBody);
        if (polygon != null) {
          _buildingPolygons[pin.id] = polygon;
          return;
        }
      }

      _buildingPolygons[pin.id] = _makeCirclePolygon(lat, lng, 80);
    } catch (_) {
      _buildingPolygons[pin.id] = _makeCirclePolygon(lat, lng, 80);
    }
  }

  List<List<double>>? _extractPolygon(Map<String, dynamic> body) {
    final elements = body['elements'] as List?;
    if (elements == null || elements.isEmpty) return null;

    List<List<double>>? parseGeom(List geom) {
      if (geom.length < 3) return null;
      return geom.map((node) {
        final n = node as Map;
        return [(n['lon'] as num).toDouble(), (n['lat'] as num).toDouble()];
      }).toList();
    }

    for (final el in elements) {
      final map = el as Map;
      final geom = map['geometry'] as List?;
      if (geom != null) {
        final poly = parseGeom(geom);
        if (poly != null) return poly;
      }
      final members = map['members'] as List?;
      if (members != null) {
        for (final member in members) {
          final m = member as Map;
          if (m['role'] == 'outer') {
            final mGeom = m['geometry'] as List?;
            if (mGeom != null) {
              final poly = parseGeom(mGeom);
              if (poly != null) return poly;
            }
          }
        }
      }
    }
    return null;
  }

  List<List<double>> _makeCirclePolygon(
    double lat, double lng, double radiusMeters, {int points = 36}
  ) {
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(lat * math.pi / 180);
    final ring = <List<double>>[];
    for (int i = 0; i <= points; i++) {
      final angle = 2 * math.pi * i / points;
      ring.add([
        lng + (radiusMeters * math.cos(angle)) / mPerDegLng,
        lat + (radiusMeters * math.sin(angle)) / mPerDegLat,
      ]);
    }
    return ring;
  }

  // ── GPS EXIF 추출 ─────────────────────────────────────────────
  Future<(geo.Position?, String)> _extractGpsFromBytes(
    Uint8List bytes,
  ) async {
    try {
      final data = await readExifFromBytes(bytes);
      if (data.isEmpty) {
        return (null, 'EXIF 데이터가 없어요.');
      }
      if (!data.containsKey('GPS GPSLatitude') ||
          !data.containsKey('GPS GPSLongitude')) {
        return (null, 'GPS 정보가 없어요.');
      }

      double? parseDMS(IfdTag tag) {
        final vals = tag.values.toList();
        if (vals.length < 3) return null;
        final deg = _toDouble(vals[0]);
        final min = _toDouble(vals[1]);
        final sec = _toDouble(vals[2]);
        if (deg == null || min == null || sec == null) return null;
        return deg + min / 60.0 + sec / 3600.0;
      }

      double? lat = parseDMS(data['GPS GPSLatitude']!);
      double? lng = parseDMS(data['GPS GPSLongitude']!);

      if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) {
        return (null, 'GPS 값을 읽을 수 없어요.');
      }
      if (data['GPS GPSLatitudeRef']?.printable == 'S') lat = -lat;
      if (data['GPS GPSLongitudeRef']?.printable == 'W') lng = -lng;

      return (geo.Position(
        latitude: lat, longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 0, altitude: 0, altitudeAccuracy: 0,
        heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
      ), '');
    } catch (e) {
      return (null, 'EXIF 읽기 오류: $e');
    }
  }

  double? _toDouble(dynamic val) {
    try {
      final n = (val as dynamic).numerator;
      final d = (val as dynamic).denominator;
      if (d == 0) return 0.0;
      return (n as num).toDouble() / (d as num).toDouble();
    } catch (_) {}
    try {
      if (val is num) return val.toDouble();
    } catch (_) {}
    try {
      final s = val.toString().trim();
      if (s.contains('/')) {
        final parts = s.split('/');
        final n = double.tryParse(parts[0]) ?? 0.0;
        final d = double.tryParse(parts[1]) ?? 1.0;
        if (d == 0) return 0.0;
        return n / d;
      }
      return double.tryParse(s);
    } catch (_) {}
    return null;
  }

  // ── 사진 추가 ─────────────────────────────────────────────────
  Future<void> addPhotoPin() async {
    if (!await Permission.accessMediaLocation.isGranted) {
      await Permission.accessMediaLocation.request();
    }
    if (!await Permission.photos.isGranted) {
      await Permission.photos.request();
    }

    final picked = await _picker.pickImage(
      source: img_picker.ImageSource.gallery,
      requestFullMetadata: true,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() => _isLoading = true);
    try {
      final rawBytes = await picked.readAsBytes();
      final (gpsResult, gpsMessage) = await _extractGpsFromBytes(rawBytes);
      geo.Position? gpsPos = gpsResult;

      if (gpsPos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('📍 $gpsMessage\n현재 위치를 사용해요.'),
            duration: const Duration(seconds: 4),
          ));
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
        photoPath: file.path,
        title: '타임캡슐 ${_pins.length + 1}',
      );
      _pins.add(pin);
      _sendPinToUnity(pin);
      await _savePins();

      // Unity 카메라를 핀 위치로 3D 이동
      _sendToUnity('FlyToPin', {
        'lat': gpsPos.latitude,
        'lng': gpsPos.longitude,
        'zoom': 18.5,
        'pitch': 65.0,
      });

      await Future.delayed(const Duration(milliseconds: 1000));
      await _queryBuildingForPin(pin);
      await _savePolygons();
      _sendFogToUnity();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
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
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (pin.photo != null && pin.photo!.existsSync())
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
              style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold,
              ),
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
          // ── Unity 3D 지도 뷰 ──────────────────────────────────
          UnityWidget(
            onUnityCreated: _onUnityCreated,
            onUnityMessage: _onUnityMessage,
            onUnitySceneLoaded: _onUnitySceneLoaded,
            useAndroidViewSurface: true,
            fullscreen: false,
          ),

          if (!_unityReady)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF7B5EA7)),
                  SizedBox(height: 16),
                  Text('3D 지도 로딩 중...', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),

          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF7B5EA7)),
              ),
            ),

          // ── 버튼 ──────────────────────────────────────────────
          Positioned(
            bottom: 100, right: 16,
            child: FloatingActionButton(
              heroTag: 'photo',
              backgroundColor: const Color(0xFF7B5EA7),
              onPressed: addPhotoPin,
              child: const Icon(Icons.add_photo_alternate, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 30, right: 16,
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
