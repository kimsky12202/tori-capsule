using System;
using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Flutter ↔ Unity 메시지 브릿지 싱글톤
///
/// flutter_unity_widget 패키지의 UnityMessageManager와 연동됩니다.
/// Flutter에서 postMessage('ToriCapsuleMap', 'MethodName', json) 을 호출하면
/// Unity의 해당 GameObject의 메서드가 직접 호출됩니다.
///
/// Unity → Flutter 전송: FlutterMessageManager.Instance.SendToFlutter(json)
/// </summary>
public class FlutterMessageManager : MonoBehaviour
{
    public static FlutterMessageManager Instance { get; private set; }

    private readonly List<Action<string>> _listeners = new();

    void Awake()
    {
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }
        Instance = this;
        DontDestroyOnLoad(gameObject);
    }

    public void AddListener(Action<string> listener) => _listeners.Add(listener);
    public void RemoveListener(Action<string> listener) => _listeners.Remove(listener);

    // flutter_unity_widget의 UnityMessageManager를 통해 Flutter로 메시지 전송
    public void SendToFlutter(string message)
    {
        try
        {
            // flutter_unity_widget 패키지 설치 후 아래 코드 활성화:
            // UnityMessageManager.Instance.SendMessageToFlutter(message);
            Debug.Log($"[→Flutter] {message}");
        }
        catch (Exception e)
        {
            Debug.LogWarning($"[FlutterMessageManager] 전송 오류: {e.Message}");
        }
    }
}
