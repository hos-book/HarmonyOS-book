import { worker, MessageEvents } from '@kit.ArkTS';
import { OfflineRecognizer, OfflineRecognizerConfig, OfflinePunctuation, OfflinePunctuationConfig } from 'sherpa_onnx';
import { decodeSubtitleAudio } from 'libsubtitle_audio.so';
import { SubtitleWorkerRequest, SubtitleWorkerResponse, SubtitleSegmenter, SUBTITLE_CHUNK_MS } from '../model/AudioSubtitle';

const port = worker.workerPort;
let recognizer: OfflineRecognizer | null = null;
let punctuation: OfflinePunctuation | null = null;
port.onmessage = (event: MessageEvents): void => {
  const request: SubtitleWorkerRequest = event.data;
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
    // The first provisional text must not wait for a second neural network to initialize.
    // The following full-context pass restores punctuation and replaces this short preview.
    if (!request.preview && !punctuation) {
      const started = Date.now();
      const config = new OfflinePunctuationConfig();
      config.model.ctTransformer = `${request.modelDir}/punctuation.int8.onnx`;
      config.model.numThreads = 1;
      punctuation = new OfflinePunctuation(config);
      console.info(`[AudioSubtitleDevice] punctuationInitMs=${Date.now() - started}`);
    }
    const chunkStart = request.chunk * SUBTITLE_CHUNK_MS;
    const startMs = request.preview ? Math.max(chunkStart, Math.min(chunkStart + 8000, request.positionMs - 500)) : chunkStart;
    const pcm = decodeSubtitleAudio(request.audioPath, startMs, request.preview ? 4000 : SUBTITLE_CHUNK_MS);
    response.chunk.endMs = pcm.endMs;
    if (pcm.samples.length > 0) {
      const stream = recognizer.createStream();
      stream.acceptWaveform({ samples: pcm.samples, sampleRate: pcm.sampleRate });
      recognizer.decode(stream);
      const result = recognizer.getResult(stream);
      response.chunk.units = SubtitleSegmenter.units(request.chunk, pcm.endMs,
        result.text, result.tokens ?? [], result.timestamps ?? [], startMs);
    }
    const previous = request.previous && request.previous.index === request.chunk - 1 ? request.previous : null;
    const prefix = previous ? request.prefix : [];
    const units = previous ? prefix.concat(previous.units, response.chunk.units) : response.chunk.units;
    const text = SubtitleSegmenter.text(units);
    const finalChunk = !request.preview && (request.finalChunk || pcm.endMs < startMs + SUBTITLE_CHUNK_MS - 100);
    const punctuated = text.trim() && !request.preview && punctuation ? punctuation.addPunct(text) : text;
    const annotated = SubtitleSegmenter.punctuate(units, punctuated, finalChunk);
    response.chunk.annotated = annotated.filter((unit): boolean => unit.startMs >= startMs);
    response.chunk.cues = SubtitleSegmenter.cues(request.chunk, annotated, finalChunk);
    if (previous) {
      previous.annotated = annotated.filter((unit): boolean =>
        unit.startMs >= previous.index * SUBTITLE_CHUNK_MS && unit.startMs < startMs);
      previous.cues = SubtitleSegmenter.cues(previous.index, annotated, false);
      response.previous = previous;
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : '';
    response.error = /^subtitle_[a-z_]+$/.test(message) ? message : 'subtitle_recognition_failed';
  }
  port.postMessage(response);
};
