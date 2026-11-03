import { ReaderFloatingLyrics } from '../components/ReaderFloatingLyrics';

@Entry
@ComponentV2
struct ReaderFloatingPage {
  build() {
    Stack() { ReaderFloatingLyrics({ systemWindow: true }) }.width('100%').height('100%')
  }
}
