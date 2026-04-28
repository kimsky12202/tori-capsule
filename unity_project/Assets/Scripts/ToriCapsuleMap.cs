using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using Mapbox.Unity.Map;
using Mapbox.Utils;
using Mapbox.Unity.MeshGeneration.Factories;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

/// <summary>
/// Flutter에서 메시지를 받아 Mapbox 3D 지도를 제어하는 메인 컨트롤러
/// GameObject 이름: "ToriCapsuleMap" (Flutter postMessage 대상)
/// </summary>
public class ToriCapsuleMap : MonoBehaviour
{
    [Header("Mapbox")]
    public AbstractMap Map;           // Inspector에서 AbstractMap 컴포넌트 연결
    public Camera MapCamera;          // 씬의 메인 카메라 연결

    [Header("Fog Overlay")]
    public FogOverlayRenderer FogRenderer;   // FogOverlayRenderer 컴포넌트 연결

    [Header("Pins")]
    public PinManager PinManager;            // PinManager 컴포넌트 연결

    // 내 위치 마커
    [Header("My Location")]
    public GameObject MyLocationPrefab;      // 파란 점 프리팹
    private GameObject _myLocMarker;

    void Start()
    {
        if (Map == null) Map = FindObjectOfType<AbstractMap>();
        if (MapCamera == null) MapCamera = Camera.main;

        // 한국 중심으로 초기화
        Map.Initialize(new Vector2d(36.48, 127.28), 6);

        // 3D 건물 및 지형 활성화는 AbstractMap Inspector에서 설정
        FlutterMessageManager.Instance.AddListener(OnFlutterMessage);
    }

    void OnDestroy()
    {
        FlutterMessageManager.Instance?.RemoveListener(OnFlutterMessage);
    }

    // ── Flutter 메시지 수신 ────────────────────────────────────────
    void OnFlutterMessage(string message)
    {
        try
        {
            var data = JObject.Parse(message);
            // 직접 메서드 이름으로 라우팅
        }
        catch (Exception e)
        {
            Debug.LogWarning($"[ToriCapsuleMap] 메시지 파싱 오류: {e.Message}");
        }
    }

    // Flutter postMessage로 직접 호출되는 메서드들 ──────────────────

    // 카메라 위치 이동
    public void MoveCamera(string json)
    {
        var d = JObject.Parse(json);
        float lat   = d["lat"].Value<float>();
        float lng   = d["lng"].Value<float>();
        float zoom  = d["zoom"]?.Value<float>() ?? 14f;
        float pitch = d["pitch"]?.Value<float>() ?? 0f;

        Map.UpdateMap(new Vector2d(lat, lng), zoom);
        StartCoroutine(AnimatePitch(pitch, 1.5f));
    }

    // 핀 위치로 부드럽게 날아가기 (3D 입체 뷰)
    public void FlyToPin(string json)
    {
        var d = JObject.Parse(json);
        float lat   = d["lat"].Value<float>();
        float lng   = d["lng"].Value<float>();
        float zoom  = d["zoom"]?.Value<float>() ?? 18.5f;
        float pitch = d["pitch"]?.Value<float>() ?? 65f;

        Map.UpdateMap(new Vector2d(lat, lng), zoom);
        StartCoroutine(AnimatePitch(pitch, 1.8f));
    }

    // 내 위치 파란 점 업데이트
    public void UpdateMyLocation(string json)
    {
        var d = JObject.Parse(json);
        double lat = d["lat"].Value<double>();
        double lng = d["lng"].Value<double>();

        var worldPos = Map.GeoToWorldPosition(new Vector2d(lat, lng), true);

        if (_myLocMarker == null && MyLocationPrefab != null)
            _myLocMarker = Instantiate(MyLocationPrefab);

        if (_myLocMarker != null)
            _myLocMarker.transform.position = worldPos;
    }

    // 핀 추가
    public void AddPin(string json)
    {
        PinManager?.AddPin(json, Map);
    }

    // 안개 GeoJSON 업데이트
    public void UpdateFog(string json)
    {
        var d = JObject.Parse(json);
        string geoJson = d["geojson"].Value<string>();
        FogRenderer?.UpdateFog(geoJson, Map);
    }

    // ── 카메라 Pitch 부드럽게 변경 ────────────────────────────────
    IEnumerator AnimatePitch(float targetPitch, float duration)
    {
        if (MapCamera == null) yield break;

        float startPitch = MapCamera.transform.eulerAngles.x;
        // Unity에서 pitch는 X 회전 (90 - pitch_degrees)
        float targetX = 90f - targetPitch;
        float elapsed = 0f;

        while (elapsed < duration)
        {
            elapsed += Time.deltaTime;
            float t = Mathf.SmoothStep(0f, 1f, elapsed / duration);
            var angles = MapCamera.transform.eulerAngles;
            angles.x = Mathf.LerpAngle(startPitch, targetX, t);
            MapCamera.transform.eulerAngles = angles;
            yield return null;
        }
    }
}
