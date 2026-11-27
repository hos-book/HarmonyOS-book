import { util } from '@kit.ArkTS';

const CELIA_BOUNDARY: string = 'hivoice-boundary';

export class ShengqiaoCeliaApp {
  ak: string;
  sk: string;
  constructor(ak: string, sk: string) { this.ak = ak; this.sk = sk; }
}

class ShengqiaoCeliaHeader {
  namespace: string;
  name: string;
  constructor(namespace: string, name: string) { this.namespace = namespace; this.name = name; }
}

class ShengqiaoCeliaDevice {
  osVersion: string = '12';
  romVersion: string = 'V417IR release-keys';
  deviceName: string = 'DCO-AL00';
  deviceType: number = 0;
  TTSVersion: string = '';
  osType: string = 'android';
  sysVersion: string = '31';
}

class ShengqiaoCeliaContext {
  header: ShengqiaoCeliaHeader = new ShengqiaoCeliaHeader('System', 'Device');
  payload: ShengqiaoCeliaDevice = new ShengqiaoCeliaDevice();
}

class ShengqiaoCeliaPayload {
  deviceId: string;
  device_supported_app_device_type: number = 0;
  text: string;
  request_id: string;
  person: number;
  language: string = 'zh';
  textType: string = 'text';
  synthesisMode: number = 0;
  compress_rate: number = 24;
  speed: number = 116;
  volume: number = 140;
  pitch: number = 100;
  audio_format: string = 'pcm';
  constructor(deviceId: string, requestId: string, sid: string, text: string) {
    this.deviceId = deviceId; this.request_id = requestId; this.person = Number(sid); this.text = text;
  }
}

class ShengqiaoCeliaEvent {
  header: ShengqiaoCeliaHeader = new ShengqiaoCeliaHeader('TTS', 'dospeak');
  payload: ShengqiaoCeliaPayload;
  constructor(deviceId: string, requestId: string, sid: string, text: string) {
    this.payload = new ShengqiaoCeliaPayload(deviceId, requestId, sid, text);
  }
}

class ShengqiaoCeliaSession {
  request_id: string;
  constructor(requestId: string) { this.request_id = requestId; }
}

export class ShengqiaoCeliaBody {
  contexts: ShengqiaoCeliaContext[] = [new ShengqiaoCeliaContext()];
  events: ShengqiaoCeliaEvent[];
  session: ShengqiaoCeliaSession;
  constructor(deviceId: string, sid: string, text: string) {
    const requestId = util.generateRandomUUID(false);
    this.events = [new ShengqiaoCeliaEvent(deviceId, requestId, sid, text)];
    this.session = new ShengqiaoCeliaSession(requestId);
  }
}

/** 小艺请求与 multipart PCM 响应沿用上游 CeliaApi 协议。 */
export class ShengqiaoCeliaProtocol {
  static readonly host: string = 'https://hivoice-drcn.emui.dbankcloud.com';
  static readonly deviceId: string = 'bcd39824-fb9a-4d30-bac9-0e26802b8d3c';

  static headers(message: string, appVersion: string): Record<string, string> {
    return {
      'receiver': 'TTS', 'sender': 'APP', 'sessionId': util.generateRandomUUID(false),
      'interactionId': '1', 'messageId': util.generateRandomUUID(false), 'locate': 'CN',
      'app-version': appVersion, 'EMUI-version': '11-0',
      'content-type': 'multipart/form-data; boundary=' + CELIA_BOUNDARY,
      'deviceId': ShengqiaoCeliaProtocol.deviceId, 'deviceType': '0',
      'deviceCategory': message === 'generateToken' ? '' : 'phone',
      'appName': 'com.huawei.vassistant', 'appVersion': '', 'messageName': message
    };
  }

  static multipart(json: string): string {
    return '--' + CELIA_BOUNDARY + '\r\nContent-Disposition: form-data; name="json"\r\n' +
      'Content-Type: application/json;charset=UTF-8\r\nContent-Length: ' +
      new util.TextEncoder().encodeInto(json).length + '\r\n\r\n' + json +
      '\r\n--' + CELIA_BOUNDARY + '--\r\n';
  }

  private static find(data: Uint8Array, marker: Uint8Array, start: number): number {
    for (let offset = start; offset <= data.length - marker.length; offset++) {
      let matched = true;
      for (let index = 0; index < marker.length; index++) {
        if (data[offset + index] !== marker[index]) { matched = false; break; }
      }
      if (matched) return offset;
    }
    return -1;
  }

  static audio(data: Uint8Array): Uint8Array | null {
    const encoder = new util.TextEncoder();
    const marker = encoder.encodeInto('--' + CELIA_BOUNDARY);
    const first = ShengqiaoCeliaProtocol.find(data, marker, 0);
    if (first < 0) return null;
    const second = ShengqiaoCeliaProtocol.find(data, marker, first + marker.length);
    if (second < 0) return null;
    const third = ShengqiaoCeliaProtocol.find(data, marker, second + marker.length);
    const part = third >= 0 ? second : first;
    const end = third >= 0 ? third : second;
    const headerEnd = ShengqiaoCeliaProtocol.find(data, encoder.encodeInto('\r\n\r\n'), part + marker.length);
    if (headerEnd < 0 || headerEnd + 4 >= end - 2) return null;
    return data.slice(headerEnd + 4, end - 2);
  }
}
