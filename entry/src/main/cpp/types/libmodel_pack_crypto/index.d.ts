/** Private release-key bridge. Caller must erase the returned buffer after conversion. */
export const getKey: () => ArrayBuffer;
export const getKeyId: () => string;
