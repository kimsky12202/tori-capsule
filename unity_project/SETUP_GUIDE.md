# Unity 3D Mapbox 지도 설정 가이드

## 1단계: 필수 설치

1. **Unity Hub** 설치 → https://unity.com/download
2. **Unity 2022.3 LTS** 버전 설치 (Android Build Support 모듈 포함)
3. 이 폴더(`unity_project`)를 Unity Hub에서 열기

---

## 2단계: Unity 패키지 설치

Unity Editor 열린 후 `Window > Package Manager`:

### Mapbox Maps SDK for Unity
1. `Add package from git URL` 클릭
2. 입력: `https://github.com/mapbox/mapbox-unity-sdk.git`
3. 설치 완료 후 `Mapbox > Setup` 메뉴에서 토큰 입력:
   ```
   pk.eyJ1IjoiPFlOUiBUOUtFTj4iLCAiYSI6ICI8WU9VUiBUT0tFTj4ifQ...
   ```
   (기존 Flutter 앱에서 쓰던 Mapbox 토큰 그대로 사용)

### flutter_unity_widget 브릿지
1. `Assets/Scripts` 폴더에 이미 `FlutterMessageManager.cs` 있음
2. `Window > Package Manager > Add from git URL`:
   `https://github.com/juicycleff/flutter-unity-view-widget.git?path=unity/FlutterUnityIntegration`

---

## 3단계: 씬 구성

### 새 씬 만들기
1. `File > New Scene` → "ToriCapsuleMap" 으로 저장
2. 기본 카메라 삭제

### Mapbox 지도 오브젝트 추가
1. `Mapbox > Map > Basic Map` 을 씬에 드래그
2. Inspector 설정:
   - **Image Layer**: Mapbox Streets (또는 Satellite Hybrid)
   - **Terrain**: Enable → Mapbox Terrain RGB
   - **Vector Layer (3D Buildings)**:
     - Add Feature Layer → `Mapbox Building With Unique Id`
     - Height: `height` 속성 연결
     - Material: 원하는 건물 머티리얼 적용
   - **Latitude/Longitude**: 36.48, 127.28 (한국 중심)
   - **Zoom**: 6

### 스크립트 연결
1. 씬에 빈 GameObject 만들기 → 이름: `ToriCapsuleMap`
2. 이 오브젝트에 스크립트 추가:
   - `ToriCapsuleMap.cs`
   - `FlutterMessageManager.cs`
3. Inspector에서 참조 연결:
   - `Map` → AbstractMap 오브젝트
   - `MapCamera` → Main Camera

4. 또 다른 빈 GameObject → `FogOverlayRenderer`
   - `FogOverlayRenderer.cs` 추가

5. 또 다른 빈 GameObject → `PinManager`
   - `PinManager.cs` 추가
   - PhotoPinPrefab, DotPinPrefab 연결 (아래에서 생성)

### 핀 프리팹 만들기
1. `3D Object > Cylinder` 생성 → 이름: `PhotoPin`
   - Scale: (0.5, 0.1, 0.5)
   - Material: 보라색 (Color: #7B5EA7)
2. Prefab으로 저장: `Assets/Prefabs/PhotoPin.prefab`
3. `PinMarker.cs` 컴포넌트 추가

---

## 4단계: Android 빌드 설정

`File > Build Settings > Android`:
- **Scripting Backend**: IL2CPP
- **Target Architecture**: ARM64, ARMv7
- `Player Settings`:
  - **Minimum API Level**: 21
  - **Package Name**: `com.example.login_test` (Flutter와 동일)

### Unity as Library 내보내기
1. `Build Settings > Export Project` 체크
2. 내보내기 경로: `<flutter_project>/unity_project/unityLibrary`
3. `Export` 클릭

---

## 5단계: Flutter 연결

내보내기 완료 후 Flutter 프로젝트로 돌아가서:

```bash
cd client-main
flutter pub get
flutter run
```

---

## 완성 구조

```
tori-capsule/
├── client-main/          ← Flutter (Dart)
│   └── lib/ui/pages/
│       └── unity_map_screen.dart   ← Unity 뷰 사용
├── unity_project/
│   ├── Assets/Scripts/   ← 이 폴더의 스크립트들
│   └── unityLibrary/     ← Unity Export 후 생성됨
```
