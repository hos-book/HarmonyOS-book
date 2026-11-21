import { worker, MessageEvents } from '@kit.ArkTS';
import { OfflineRecognizer, OfflineRecognizerConfig, OfflinePunctuation, OfflinePunctuationConfig } from 'sherpa_onnx';
import { decodeSubtitleAudio } from 'libsubtitle_audio.so';
import { SubtitleWorkerRequest, SubtitleWorkerResponse, SubtitleUnit, SubtitleSegmenter,
  SUBTITLE_CHUNK_MS, SUBTITLE_CONTEXT_MS } from '../model/AudioSubtitle';

const port = worker.workerPort;
let recognizer: OfflineRecognizer | null = null;
let punctuation: OfflinePunctuation | null = null;
port.onmessage = (event: MessageEvents): void => {
  const request: SubtitleWorkerRequest = event.data;
  // 排在同步 native 推理之后执行，避免在推理/解码过程中销毁 Worker 环境。
  if (request.shutdown) {
    recognizer = null;
    punctuation = null;
    port.close();
    return;
  }
  const response = new SubtitleWorkerResponse();
  response.requestId = request.requestId;
  response.preview = request.preview;
  response.chunk.index = request.chunk;
  try {
    if (!recognizer) {
      const started = Date.now();
      const config = new OfflineRecognizerConfig();
      config.modelConfig.zipformerCtc.model = `${request.modelDir}/model.int8.onnx`;
      config.modelConfig.tokens = `${request.modelDir}/tokens.txt`;
      config.modelConfig.numThreads = 2;
      config.modelConfig.provider = 'cpu';
      recognizer = new OfflineRecognizer(config);
      console.info(`[AudioSubtitleDevice] recognizerInitMs=${Date.now() - started}`);
    }
    // A short preview precedes punctuation initialization and full-context recognition.
    if (!request.preview && !punctuation) {
      const started = Date.now();
      const config = new OfflinePunctuationConfig();
      config.model.ctTransformer = `${request.modelDir}/punctuation.int8.onnx`;
      config.model.numThreads = 1;
      punctuation = new OfflinePunctuation(config);
      console.info(`[AudioSubtitleDevice] punctuationInitMs=${Date.now() - started}`);
    }
    const chunkStart = request.chunk * SUBTITLE_CHUNK_MS;
    const chunkEnd = chunkStart + SUBTITLE_CHUNK_MS;
    const startMs = request.preview ? Math.max(chunkStart, Math.min(chunkStart + 8000, request.positionMs - 500)) :
      Math.max(0, chunkStart - SUBTITLE_CONTEXT_MS);
    const windowEnd = request.preview ? startMs + 4000 : chunkEnd + SUBTITLE_CONTEXT_MS;
    const pcm = decodeSubtitleAudio(request.audioPath, startMs, windowEnd - startMs);
    response.chunk.endMs = Math.min(pcm.endMs, chunkEnd);
    let recognized: SubtitleUnit[] = [];
    if (pcm.samples.length > 0) {
      const stream = recognizer.createStream();
      stream.acceptWaveform({ samples: pcm.samples, sampleRate: pcm.sampleRate });
      recognizer.decode(stream);
      const result = recognizer.getResult(stream);
      recognized = SubtitleSegmenter.units(request.chunk, pcm.endMs,
        result.text, result.tokens ?? [], result.timestamps ?? [], startMs);
    }
    const previous = !request.preview && request.previous && request.previous.index === request.chunk - 1 ? request.previous : null;
    const prefix = previous ? request.prefix : [];
    const joined = previous ? SubtitleSegmenter.join(previous.units, recognized, chunkStart) : recognized;
    response.chunk.units = SubtitleSegmenter.owned(request.chunk, joined);
    const units = prefix.concat(joined);
    const text = SubtitleSegmenter.text(units);
    const finalChunk = !request.preview && (request.finalChunk || pcm.endMs < windowEnd - 100);
    const punctuated = text.trim() && !request.preview && punctuation ? punctuation.addPunct(text) : text;
    const annotated = SubtitleSegmenter.punctuate(units, punctuated, finalChunk);
    response.chunk.annotated = SubtitleSegmenter.owned(request.chunk, annotated);
    response.chunk.cues = SubtitleSegmenter.cues(request.chunk, response.chunk.annotated, finalChunk && pcm.endMs <= chunkEnd);
    if (previous) {
      previous.units = SubtitleSegmenter.owned(previous.index, joined);
      previous.annotated = SubtitleSegmenter.owned(previous.index, annotated);
      previous.cues = SubtitleSegmenter.cues(previous.index, previous.annotated, false);
      response.previous = previous;
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    response.error = /^subtitle_[a-z_]+$/.test(message) ? message : 'subtitle_recognition_failed';
  }
  port.postMessage(response);
};
