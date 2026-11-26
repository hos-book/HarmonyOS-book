// Keep search selection and reader actions in the existing application services.
module.exports = function applicationScope(name, text) {
  if (name === 'core/book/SearchCoordinator.ts') {
    text = text.replace("import { SourceFormProfile } from './SourceFormProfile';\n", '')
      .replace(/^ +if \(book\.name && book\.bookUrl\) SourceFormProfile\.note\([^\n]+\);\n/gm, '');
  }
  if (name === 'core/book/WebBookService.ts') {
    text = text.replace("import { MixedVideoChapter } from './MixedVideoChapter';\n", '')
      .replace(/^ +\/\/[^\n]+\n +if \(!debugContext && MixedVideoChapter\.isMixedVideo\(book, chapter\)\) return MixedVideoChapter\.cardText\(chapter\);\n/m, '');
  }
  return text;
};
