export interface RoleNnrtPrediction {
  output: ArrayBuffer;
  backend: string;
}
export const loadRoleNnrtModel: (path: string) => Promise<string>;
export const predictRoleNnrtModel: (inputIds: ArrayBuffer, tokenTypes: ArrayBuffer,
  attentionMask: ArrayBuffer) => Promise<RoleNnrtPrediction>;
export const releaseRoleNnrtModel: () => Promise<void>;
