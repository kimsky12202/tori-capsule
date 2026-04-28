using System;
using System.Collections.Generic;
using UnityEngine;
using Mapbox.Unity.Map;
using Mapbox.Utils;
using Newtonsoft.Json.Linq;

/// <summary>
/// 사진 핀을 Mapbox 3D 지도 위에 배치하고 관리합니다.
/// 핀 탭 시 Flutter로 이벤트를 전송합니다.
/// </summary>
public class PinManager : MonoBehaviour
{
    [Header("Pin Prefabs")]
    public GameObject PhotoPinPrefab;  // 사진 핀 3D 프리팹 (원형 사진 + 꼬리)
    public GameObject DotPinPrefab;    // 사진 없는 기본 핀 프리팹

    private readonly Dictionary<string, GameObject> _pinObjects = new();
    private AbstractMap _map;

    void Update()
    {
        // 지도 이동/줌에 따라 핀 위치 갱신
        if (_map == null) return;
        foreach (var (id, go) in _pinObjects)
        {
            if (go == null) continue;
            var pinComp = go.GetComponent<PinMarker>();
            if (pinComp != null)
            {
                go.transform.position = _map.GeoToWorldPosition(
                    new Vector2d(pinComp.Lat, pinComp.Lng), true
                );
            }
        }
    }

    public void AddPin(string json, AbstractMap map)
    {
        _map = map;
        try
        {
            var d = JObject.Parse(json);
            string id        = d["id"].Value<string>();
            double lat       = d["lat"].Value<double>();
            double lng       = d["lng"].Value<double>();
            string title     = d["title"]?.Value<string>() ?? "";
            string photoPath = d["photoPath"]?.Value<string>() ?? "";

            // 기존 핀이 있으면 제거
            if (_pinObjects.TryGetValue(id, out var existing))
            {
                Destroy(existing);
                _pinObjects.Remove(id);
            }

            var prefab  = (string.IsNullOrEmpty(photoPath) || !System.IO.File.Exists(photoPath))
                          ? DotPinPrefab : PhotoPinPrefab;
            if (prefab == null) return;

            var worldPos = map.GeoToWorldPosition(new Vector2d(lat, lng), true);
            var pinGo    = Instantiate(prefab, worldPos, Quaternion.identity, transform);
            pinGo.name   = $"Pin_{id}";

            // PinMarker 컴포넌트에 데이터 저장
            var marker = pinGo.GetComponent<PinMarker>() ?? pinGo.AddComponent<PinMarker>();
            marker.PinId    = id;
            marker.Lat      = lat;
            marker.Lng      = lng;
            marker.Title    = title;
            marker.PhotoPath = photoPath;
            marker.OnTapped = OnPinTapped;

            // 사진이 있으면 텍스처 적용
            if (!string.IsNullOrEmpty(photoPath) && System.IO.File.Exists(photoPath))
                StartCoroutine(LoadPhotoTexture(pinGo, photoPath));

            _pinObjects[id] = pinGo;
        }
        catch (Exception e)
        {
            Debug.LogWarning($"[PinManager] AddPin 오류: {e.Message}");
        }
    }

    void OnPinTapped(string pinId)
    {
        // Flutter로 핀 탭 이벤트 전송
        var msg = $"{{\"type\":\"pinTapped\",\"id\":\"{pinId}\"}}";
        FlutterMessageManager.Instance?.SendToFlutter(msg);
    }

    System.Collections.IEnumerator LoadPhotoTexture(GameObject pinGo, string path)
    {
        yield return null; // 한 프레임 대기

        var www = new WWW("file://" + path);
        yield return www;

        if (string.IsNullOrEmpty(www.error))
        {
            var renderer = pinGo.GetComponentInChildren<Renderer>();
            if (renderer != null)
            {
                var tex = www.texture;
                renderer.material.mainTexture = tex;
            }
        }
    }
}
