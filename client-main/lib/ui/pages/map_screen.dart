import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:image_picker/image_picker.dart' as img_picker;
import 'package:exif/exif.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui' show ImageByteFormat, PictureRecorder;
import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'fog_painter.dart';

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
    'id': id,
    'lat': lat,
    'lng': lng,
    'photoPath': photoPath,
    'title': title,
  };

  factory CapsulePin.fromJson(Map<String, dynamic> j) => CapsulePin(
    id: j['id'] as String,
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    photoPath: j['photoPath'] as String?,
    title: j['title'] as String,
  );
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
  static const String _prefsKey = 'capsule_pins';

  MapboxMap? _map;
  PointAnnotationManager? _pinManager;
  PointAnnotationManager? _myLocManager;
  PointAnnotation? _myLocMarker;

  final List<CapsulePin> _pins = [];
  final Map<String, String> _markerMap = {};
  // 핀ID → 건물 GeoJSON 좌표 [[lng,lat], ...]
  final Map<String, List<List<double>>> _buildingPolygons = {};
  final img_picker.ImagePicker _picker = img_picker.ImagePicker();
  StreamSubscription<geo.Position>? _posSub;
  Timer? _overlayTimer;

  bool _isLoading = false;
  bool _tapListenerRegistered = false;
  List<HoleShape> _holeShapes = [];
  static const double _holeRadius = 300.0;
  static const double _minZoomToShow = 11.0;

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
    _overlayTimer?.cancel();
    super.dispose();
  }

  // ── 핀 위치 → 화면 좌표 변환 (오버레이 구멍) ────────────────
  void _startOverlayTimer() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _updateHoleOffsets(),
    );
  }

  Future<void> _updateHoleOffsets() async {
    if (_map == null || _pins.isEmpty) {
      if (_holeShapes.isNotEmpty && mounted) setState(() => _holeShapes = []);
      return;
    }
    double zoom = 0;
    try { zoom = (await _map!.getCameraState()).zoom; } catch (_) {}

    if (zoom < _minZoomToShow) {
      if (mounted) setState(() => _holeShapes = []);
      return;
    }

    final shapes = <HoleShape>[];
    for (final pin in _pins) {
      try {
        final sc = await _map!.pixelForCoordinate(
          Point(coordinates: Position(pin.lng, pin.lat)),
        );
        final center = Offset(sc.x, sc.y);

        // 건물 폴리곤이 있으면 화면 좌표로 변환
        final geoPolygon = _buildingPolygons[pin.id];
        List<Offset>? screenPolygon;
        if (geoPolygon != null) {
          final pts = <Offset>[];
          for (final coord in geoPolygon) {
            try {
              final pt = await _map!.pixelForCoordinate(
                Point(coordinates: Position(coord[0], coord[1])),
              );
              pts.add(Offset(pt.x, pt.y));
            } catch (_) {}
          }
          if (pts.length >= 3) screenPolygon = pts;
        }

        shapes.add(HoleShape(center: center, polygon: screenPolygon));
      } catch (_) {}
    }
    if (mounted) setState(() => _holeShapes = shapes);
  }

  /// 좌표를 포함하는 OSM 폴리곤 geometry 추출 헬퍼
  List<List<double>>? _extractPolygon(Map<String, dynamic> body) {
    final elements = body['elements'] as List?;
    if (elements == null || elements.isEmpty) return null;
    for (final el in elements) {
      final geometry = (el as Map)['geometry'] as List?;
      if (geometry == null || geometry.length < 3) continue;
      return geometry.map((node) {
        final n = node as Map;
        return [(n['lon'] as num).toDouble(), (n['lat'] as num).toDouble()];
      }).toList();
    }
    return null;
  }

  /// OSM Overpass API로 아파트 단지 → 개별 건물 순으로 폴리곤 가져오기
  Future<void> _queryBuildingForPin(CapsulePin pin) async {
    Future<Map<String, dynamic>?> query(String q) async {
      try {
        final url = Uri.parse(
          'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(q)}',
        );
        final res = await http.get(url).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      return null;
    }

    try {
      // 1단계: 해당 좌표를 포함하는 아파트 단지(landuse=residential) 경계
      final complexQ =
          '[out:json];is_in(${pin.lat},${pin.lng})->.a;'
          '(way["landuse"="residential"](pivot.a);'
          'way["landuse"="apartments"](pivot.a););'
          'out geom;';
      final complexBody = await query(complexQ);
      if (complexBody != null) {
        final polygon = _extractPolygon(complexBody);
        if (polygon != null) {
          _buildingPolygons[pin.id] = polygon;
          debugPrint('✅ 아파트 단지 폴리곤: ${polygon.length}개 꼭짓점');
          return;
        }
      }

      // 2단계: 단지 경계 없으면 반경 30m 내 개별 건물
      final buildingQ =
          '[out:json];way["building"](around:30,${pin.lat},${pin.lng});out geom;';
      final buildingBody = await query(buildingQ);
      if (buildingBody != null) {
        final polygon = _extractPolygon(buildingBody);
        if (polygon != null) {
          _buildingPolygons[pin.id] = polygon;
          debugPrint('✅ 개별 건물 폴리곤: ${polygon.length}개 꼭짓점');
          return;
        }
      }

      debugPrint('건물/단지 없음 → 원형 사용');
    } catch (e) {
      debugPrint('건물 쿼리 오류: $e');
    }
  }

  // ── 저장/불러오기 ─────────────────────────────────────────
  Future<void> _savePins() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _pins.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_prefsKey, list);
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? [];
    for (final raw in list) {
      try {
        final pin = CapsulePin.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        // 파일이 아직 존재하는 것만 복원
        if (pin.photoPath == null || File(pin.photoPath!).existsSync()) {
          _pins.add(pin);
          await _addMarkerToMap(pin);
          await _queryBuildingForPin(pin);
        }
      } catch (_) {}
    }
  }

  Future<void> _addMarkerToMap(CapsulePin pin) async {
    _pinManager ??= await _map?.annotations.createPointAnnotationManager();
    Uint8List markerImg;
    if (pin.photo != null && pin.photo!.existsSync()) {
      markerImg = await _makePhotoMarker(pin.photo!);
    } else {
      markerImg = await _makeDotImage(color: const Color(0xFF7B5EA7));
    }
    final marker = await _pinManager?.create(
      PointAnnotationOptions(
        geometry: Point(coordinates: Position(pin.lng, pin.lat)),
        image: markerImg,
        iconSize: 0.8,
      ),
    );
    if (marker != null) _markerMap[pin.id] = marker.id;
    _registerTapListener();
  }

  // ── 지도 초기화 ───────────────────────────────────────────
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
    await _loadPins();
    _startOverlayTimer();
    // 아침 모드 (오버레이로 핀 없는 곳을 어둡게)
    try {
      await map.style.setStyleImportConfigProperty('basemap', 'lightPreset', 'dawn');
    } catch (_) {}
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
        image: await _makeDotImage(color: const Color(0xFF4A90E2)),
        iconSize: 1.0,
      ),
    );
  }

  Future<Uint8List> _makeDotImage({required Color color}) async {
    final rec = PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, 40, 40));
    c.drawCircle(const Offset(20, 20), 18, Paint()..color = Colors.white);
    c.drawCircle(const Offset(20, 20), 13, Paint()..color = color);
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

  // ── GPS EXIF 추출 ─────────────────────────────────────────
  Future<(geo.Position?, String)> _extractGpsFromPhoto(File photo) async {
    try {
      final bytes = await photo.readAsBytes();
      final data = await readExifFromBytes(bytes);

      if (data.isEmpty) {
        return (null, 'EXIF 데이터가 없어요. 카메라로 직접 찍은 사진을 써보세요.');
      }
      if (!data.containsKey('GPS GPSLatitude') || !data.containsKey('GPS GPSLongitude')) {
        return (null, 'GPS 정보가 없어요. 카메라 설정에서 "위치 태그"를 켜고 직접 찍은 사진을 써보세요.');
      }

      final latRaw = data['GPS GPSLatitude']!.values.toList();
      final lngRaw = data['GPS GPSLongitude']!.values.toList();
      debugPrint('GPS lat raw: $latRaw (types: ${latRaw.map((e) => e.runtimeType).toList()})');
      debugPrint('GPS lng raw: $lngRaw (types: ${lngRaw.map((e) => e.runtimeType).toList()})');
      debugPrint('GPS lat ref: ${data['GPS GPSLatitudeRef']?.printable}');
      debugPrint('GPS lng ref: ${data['GPS GPSLongitudeRef']?.printable}');

      double? parseDMS(IfdTag tag) {
        final vals = tag.values.toList();
        if (vals.length < 3) return null;
        final deg = _toDouble(vals[0]);
        final min = _toDouble(vals[1]);
        final sec = _toDouble(vals[2]);
        debugPrint('  DMS: deg=$deg, min=$min, sec=$sec');
        if (deg == null || min == null || sec == null) return null;
        return deg + min / 60.0 + sec / 3600.0;
      }

      double? lat = parseDMS(data['GPS GPSLatitude']!);
      double? lng = parseDMS(data['GPS GPSLongitude']!);

      debugPrint('GPS 파싱 결과: lat=$lat, lng=$lng');

      if (lat == null || lng == null) {
        return (null, 'GPS 값을 읽을 수 없어요.');
      }
      if (data['GPS GPSLatitudeRef']?.printable == 'S') lat = -lat;
      if (data['GPS GPSLongitudeRef']?.printable == 'W') lng = -lng;

      return (geo.Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 0, altitude: 0, altitudeAccuracy: 0,
        heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
      ), '');
    } catch (e) {
      debugPrint('EXIF 오류: $e');
      return (null, 'EXIF 읽기 오류: $e');
    }
  }

  // Ratio / num / String 모두 처리
  double? _toDouble(dynamic val) {
    try {
      // exif Ratio 타입: numerator, denominator 프로퍼티
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
            .firstWhere((e) => e.value == tapped.id, orElse: () => const MapEntry('', ''))
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

  // ── 사진 추가 ─────────────────────────────────────────────
  Future<void> addPhotoPin() async {
    final picked = await _picker.pickImage(
      source: img_picker.ImageSource.gallery,
      requestFullMetadata: true,
    );
    if (picked == null) return;
    final file = File(picked.path);
    setState(() => _isLoading = true);
    try {
      final (gpsResult, gpsMessage) = await _extractGpsFromPhoto(file);
      geo.Position? gpsPos = gpsResult;

      if (gpsPos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📍 $gpsMessage\n현재 위치를 대신 사용해요.'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        gpsPos = await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
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
      await _addMarkerToMap(pin);
      await _savePins();

      // 핀 위치로 카메라 이동 (zoom 16 = 건물 명확히 보임)
      await _map?.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(gpsPos.longitude, gpsPos.latitude)),
          zoom: 16.0,
        ),
        MapAnimationOptions(duration: 1000),
      );

      // 이동 완료 + 건물 타일 로드 대기 후 건물 쿼리
      await Future.delayed(const Duration(milliseconds: 800));
      await _queryBuildingForPin(pin);
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
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            if (pin.photo != null && pin.photo!.existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(pin.photo!, height: 200, width: double.infinity, fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),
            Text(pin.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
          // 핀 근처만 아침처럼, 나머지는 야간처럼 보이는 오버레이
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: NightOverlayPainter(
                  holes: _holeShapes,
                  circleRadius: _holeRadius,
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator(color: Color(0xFF7B5EA7))),
            ),
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
