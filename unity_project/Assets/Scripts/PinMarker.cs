using System;
using UnityEngine;

/// <summary>
/// 각 핀 GameObject에 부착되는 데이터 컴포넌트 + 탭 감지
/// </summary>
public class PinMarker : MonoBehaviour
{
    public string PinId;
    public double Lat;
    public double Lng;
    public string Title;
    public string PhotoPath;
    public Action<string> OnTapped;

    void OnMouseDown()
    {
        OnTapped?.Invoke(PinId);
    }
}
