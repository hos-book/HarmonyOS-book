import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { mindSporeLite } from '@kit.MindSporeLiteKit';

class ColorBackendProbe {
  static readonly WIDTH: number = 512;
  static readonly HEIGHT: number = 768;

  static input(): Float32Array {
    const data = new Float32Array(ColorBackendProbe.WIDTH * ColorBackendProbe.HEIGHT * 5);
    for (let y = 0; y < ColorBackendProbe.HEIGHT; y++) {
      for (let x = 0; x < ColorBackendProbe.WIDTH; x++) {
        const ellipse = ((x - 256) / 150) ** 2 + ((y - 250) / 150) ** 2;
        const line = (x > 16 && x < 496 && (Math.abs(y - 16) < 3 || Math.abs(y - 500) < 3 ||
          Math.abs(y - 516) < 3 || Math.abs(y - 720) < 3)) ||
          (y > 16 && y < 720 && (Math.abs(x - 16) < 3 || Math.abs(x - 496) < 3));
        let gray = ellipse < 1 ? 0.7 + 0.2 * (y / 768) : 1;
        if (y > 530 && y < 690 && x > 32 && x < 480) {
          gray = ((x * 73 + y * 113) % 256) / 255;
        }
        if (line || Math.abs(ellipse - 1) < 0.04 ||
          (y > 195 && y < 220 && (Math.abs(x - 180) < 12 || Math.abs(x - 330) < 12))) gray = 0;
        data[(y * ColorBackendProbe.WIDTH + x) * 5] = gray;
      }
    }
    return data;
  }

  static async predict(context: common.Context, label: string, filename: string, input: Float32Array,
    config: mindSporeLite.Context): Promise<Float32Array> {
    const modelBytes = await context.resourceManager.getRawFileContent(`comic-colorizer/${filename}`);
    const started = Date.now();
    const model = await mindSporeLite.loadModelFromBuffer(
      modelBytes.buffer.slice(modelBytes.byteOffset, modelBytes.byteOffset + modelBytes.byteLength), config);
    const initial = model.getInputs();
    if (initial[0].shape.join(',') !== '1,768,512,5') {
      expect(model.resize(initial, [[1, 768, 512, 5]])).assertTrue();
    }
    const inputs = model.getInputs();
    inputs[0].setData(input.buffer);
    const predicting = Date.now();
    const outputs = await model.predict(inputs);
    expect(outputs.length).assertEqual(1);
    expect(outputs[0].dtype).assertEqual(mindSporeLite.DataType.NUMBER_TYPE_FLOAT32);
    console.info(`[NpuProbe] ${label} load=${predicting - started}ms infer=${Date.now() - predicting}ms ` +
      `input=${inputs[0].shape.join(',')} output=${outputs[0].shape.join(',')}`);
    const raw = new Float32Array(outputs[0].getData());
    const colors = new Float32Array(raw.length);
    const count = ColorBackendProbe.WIDTH * ColorBackendProbe.HEIGHT;
    expect(raw.length).assertEqual(count * 3);
    if (outputs[0].shape.join(',') === '1,3,768,512') {
      for (let i = 0; i < count; i++) {
        colors[i * 3] = raw[i];
        colors[i * 3 + 1] = raw[count + i];
        colors[i * 3 + 2] = raw[count * 2 + i];
      }
    } else {
      expect(outputs[0].shape.join(',')).assertEqual('1,768,512,3');
      colors.set(raw);
    }
    return colors;
  }

  static compare(label: string, actual: Float32Array, reference: Float32Array): boolean {
    let sum = 0;
    let bottom = 0;
    let maximum = 0;
    let invalid = 0;
    const bottomStart = Math.floor(ColorBackendProbe.HEIGHT * 0.8) * ColorBackendProbe.WIDTH * 3;
    const rowErrors: number[] = [];
    for (let y = 0; y < ColorBackendProbe.HEIGHT; y++) {
      let rowSum = 0;
      for (let i = y * ColorBackendProbe.WIDTH * 3; i < (y + 1) * ColorBackendProbe.WIDTH * 3; i++) {
        if (!Number.isFinite(actual[i]) || !Number.isFinite(reference[i])) invalid++;
        const error = Math.abs(actual[i] - reference[i]);
        sum += error;
        rowSum += error;
        maximum = Math.max(maximum, error);
        if (i >= bottomStart) bottom += error;
      }
      if (y % 64 === 0 || y === ColorBackendProbe.HEIGHT - 1) rowErrors.push(rowSum / (ColorBackendProbe.WIDTH * 3));
    }
    console.info(`[NpuProbe] ${label} mae=${sum / actual.length} bottom=${bottom / (actual.length - bottomStart)} ` +
      `max=${maximum} invalid=${invalid} rows=${JSON.stringify(rowErrors)}`);
    expect(invalid).assertEqual(0);
    return sum / actual.length <= 0.03 && bottom / (actual.length - bottomStart) <= 0.03;
  }
}

export default function comicColorBackendTest(): void {
  describe('ComicColorBackendDevice', () => {
    it('isolates_model_conversion_from_nnrt_execution', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      const devices = mindSporeLite.getAllNNRTDeviceDescriptions();
      const device = devices.find((item: mindSporeLite.NNRTDeviceDescription): boolean =>
        item.deviceType() === mindSporeLite.NNRTDeviceType.NNRTDEVICE_ACCELERATOR);
      if (!device) throw new Error('The diagnostic requires an NNRT accelerator');
      console.info(`[NpuProbe] device=${device.deviceName()} id=${device.deviceID().toString()}`);
      const cpu16: mindSporeLite.Context = { target: ['cpu'], cpu: { threadNum: 4, precisionMode: 'preferred_fp16' } };
      const cpu32: mindSporeLite.Context = { target: ['cpu'], cpu: { threadNum: 4 } };
      const nnrt: mindSporeLite.Context = { target: ['nnrt', 'cpu'], cpu: { threadNum: 4, precisionMode: 'preferred_fp16' },
        nnrt: { deviceID: device.deviceID(), performanceMode: mindSporeLite.PerformanceMode.PERFORMANCE_HIGH } };
      const input = ColorBackendProbe.input();
      const reference = await ColorBackendProbe.predict(context, 'dynamic_cpu16', 'alac.ms', input, cpu16);
      const fixed = await ColorBackendProbe.predict(context, 'fixed_cpu16', 'alac-npu-portrait.ms', input, cpu16);
      ColorBackendProbe.compare('fixed_cpu16_vs_dynamic_cpu16', fixed, reference);
      const accelerated = await ColorBackendProbe.predict(context, 'fixed_nnrt', 'alac-npu-portrait.ms', input, nnrt);
      ColorBackendProbe.compare('nnrt_vs_fixed_cpu16', accelerated, fixed);
      ColorBackendProbe.compare('nnrt_vs_dynamic_cpu16', accelerated, reference);
      const precise = await ColorBackendProbe.predict(context, 'dynamic_cpu32', 'alac.ms', input, cpu32);
      ColorBackendProbe.compare('dynamic_cpu16_vs_cpu32', reference, precise);
      expect(ColorBackendProbe.compare('nnrt_vs_dynamic_cpu32', accelerated, precise)).assertTrue();
      console.info('[NpuProbe] DONE');
    });
  });
}
