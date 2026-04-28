using System;
using System.Collections.Generic;
using UnityEngine;
using Mapbox.Unity.Map;
using Mapbox.Utils;
using Newtonsoft.Json.Linq;

/// <summary>
/// GeoJSON Polygon (세계 외부 링 + 구멍 링) 을 받아
/// Unity Mesh로 안개 오버레이를 렌더링합니다.
///
/// 동작 원리:
///   - 전 세계를 덮는 큰 사각형 메시에 어두운 반투명 머티리얼 적용
///   - 사진 핀 폴리곤 위치만 메시에서 잘라내어(Hole) 밝게 보이도록
/// </summary>
[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class FogOverlayRenderer : MonoBehaviour
{
    [Header("Fog Settings")]
    [Range(0f, 1f)]
    public float FogOpacity = 0.85f;
    public Color FogColor = new Color(0.02f, 0.06f, 0.12f, 0.85f);

    private MeshFilter   _mf;
    private MeshRenderer _mr;
    private Material     _mat;
    private AbstractMap  _map;

    void Awake()
    {
        _mf = GetComponent<MeshFilter>();
        _mr = GetComponent<MeshRenderer>();

        // 반투명 Unlit 셰이더로 머티리얼 생성
        _mat = new Material(Shader.Find("Unlit/Transparent"));
        _mat.color = new Color(FogColor.r, FogColor.g, FogColor.b, FogOpacity);
        _mr.material = _mat;
        _mr.sortingOrder = 100;
    }

    // Flutter에서 GeoJSON 문자열 수신
    public void UpdateFog(string geoJson, AbstractMap map)
    {
        _map = map;
        try
        {
            var feature = JObject.Parse(geoJson);
            var coords  = feature["geometry"]["coordinates"] as JArray;
            if (coords == null || coords.Count == 0) return;

            BuildMesh(coords);
        }
        catch (Exception e)
        {
            Debug.LogWarning($"[FogOverlay] GeoJSON 파싱 오류: {e.Message}");
        }
    }

    // ── GeoJSON 좌표 → Unity Mesh ──────────────────────────────────
    void BuildMesh(JArray rings)
    {
        var vertices  = new List<Vector3>();
        var triangles = new List<int>();

        // ring[0] = 외부 링 (전 세계 커버)
        // ring[1+] = 구멍 링 (핀 위치)
        var outerRing = GeoRingToWorld(rings[0] as JArray);
        if (outerRing == null || outerRing.Count < 3) return;

        // 구멍 링들
        var holes = new List<List<Vector3>>();
        for (int i = 1; i < rings.Count; i++)
        {
            var holeVerts = GeoRingToWorld(rings[i] as JArray);
            if (holeVerts != null && holeVerts.Count >= 3)
                holes.Add(holeVerts);
        }

        // Earcut 삼각분할 (외부 - 내부 구멍)
        Triangulate(outerRing, holes, vertices, triangles);

        var mesh = new Mesh { name = "FogMesh" };
        mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
        mesh.SetVertices(vertices);
        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateNormals();

        _mf.mesh = mesh;
        transform.position = new Vector3(0, 200f, 0); // 카메라 위 높이 (항상 보임)
    }

    List<Vector3> GeoRingToWorld(JArray ring)
    {
        if (ring == null || _map == null) return null;
        var result = new List<Vector3>();
        foreach (var pt in ring)
        {
            double lng = pt[0].Value<double>();
            double lat = pt[1].Value<double>();
            var worldPos = _map.GeoToWorldPosition(new Vector2d(lat, lng), true);
            result.Add(worldPos);
        }
        return result;
    }

    // ── Earcut 삼각분할 (구멍 포함) ───────────────────────────────
    void Triangulate(
        List<Vector3> outer,
        List<List<Vector3>> holes,
        List<Vector3> outVerts,
        List<int> outTris
    )
    {
        int baseIdx = outVerts.Count;
        outVerts.AddRange(outer);

        // 구멍이 없으면 팬 삼각분할
        if (holes.Count == 0)
        {
            for (int i = 1; i < outer.Count - 1; i++)
            {
                outTris.Add(baseIdx);
                outTris.Add(baseIdx + i);
                outTris.Add(baseIdx + i + 1);
            }
            return;
        }

        // 구멍 포함: Bridge 방식으로 연결 후 팬 삼각분할
        // (간단한 구현: 외부 폴리곤과 각 구멍을 연결선으로 합침)
        var combined = new List<Vector3>(outer);
        foreach (var hole in holes)
        {
            // 가장 가까운 외부 꼭짓점과 구멍의 꼭짓점을 찾아 연결
            int outerIdx = FindClosestVertex(combined, hole[0]);
            int insertAt = outerIdx + 1;

            // Bridge: outer[outerIdx] → hole[0] → ... → hole[n] → hole[0] → outer[outerIdx]
            combined.InsertRange(insertAt, hole);
            combined.Insert(insertAt + hole.Count, hole[0]);
            combined.Insert(insertAt + hole.Count + 1, combined[outerIdx]);
        }

        // 팬 삼각분할
        for (int i = 1; i < combined.Count - 1; i++)
        {
            outTris.Add(baseIdx);
            outTris.Add(baseIdx + i);
            outTris.Add(baseIdx + i + 1);
        }
        outVerts.AddRange(combined.GetRange(outer.Count, combined.Count - outer.Count));
    }

    int FindClosestVertex(List<Vector3> polygon, Vector3 point)
    {
        int closest = 0;
        float minDist = float.MaxValue;
        for (int i = 0; i < polygon.Count; i++)
        {
            float d = Vector3.Distance(polygon[i], point);
            if (d < minDist) { minDist = d; closest = i; }
        }
        return closest;
    }
}
