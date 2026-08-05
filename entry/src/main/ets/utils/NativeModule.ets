import nativeModule from 'libnative_module.so';

interface AudioMetadata {
  title: string;
  artist: string;
  album: string;
  duration: number;
  sampleRate: number;
  channels: number;
}

interface DeviceInfo {
  brand: string;
  osType: string;
}

export class NativeUtils {
  private static instance: NativeUtils | null = null;

  private constructor() {
  }

  static getInstance(): NativeUtils {
    if (!NativeUtils.instance) {
      NativeUtils.instance = new NativeUtils();
    }
    return NativeUtils.instance;
  }

  public add(a: number, b: number): number {
    return nativeModule.add(a, b);
  }

  public parseAudioMetadata(filePath: string): AudioMetadata {
    return nativeModule.parseAudioMetadata(filePath);
  }

  public getDeviceInfo(): DeviceInfo {
    return nativeModule.getDeviceInfo();
  }
}
