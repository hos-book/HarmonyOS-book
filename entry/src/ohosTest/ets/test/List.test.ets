import comicColorBackendTest from './ComicColorBackend.test';
import audioSubtitleTest from './AudioSubtitle.test';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import localBookImportTest from './LocalBookImport.test';
import comicTranslationTest from './ComicTranslation.test';
import comicOfflineTranslationTest from './ComicOfflineTranslation.test';
import imageStripTransformTest from './ImageStripTransform.test';
import localRuleQuickJsHostTest from './LocalRuleQuickJsHost.test';
import localRuleSourceFileImportTest from './LocalRuleSourceFileImport.test';
import abilityTest from './Ability.test';
import localRulePersistenceTest from './LocalRulePersistence.test';
import localRuleBrowserIntegrationTest from './LocalRuleBrowserIntegration.test';
import sourcePlaybackSmokeTest from './SourcePlaybackSmoke.test';
import localRuleSourceBulkTesterTest from '../../../test/LocalRuleSourceBulkTester.test';
import localRuleSourceRepositoryTest from '../../../test/LocalRuleSourceRepository.test';
import localRuleTlsTrustTest from '../../../test/LocalRuleTlsTrust.test';
import localRuleManagementIntegrationTest from './LocalRuleManagementIntegration.test';
import localRuleBrowserLoginCoordinatorTests from '../../../test/LocalRuleBrowserLoginCoordinator.test';

export default function testsuite() {
  const args = abilityDelegatorRegistry.getArguments().parameters;
  const selectedSuite = args['-s class'] ?? args.class;
  if (selectedSuite === 'AudioSubtitleDevice' || selectedSuite === 'AudioSubtitleMp3Device') {
    audioSubtitleTest();
    return;
  }
  if (selectedSuite === 'ComicColorBackendDevice') {
    comicColorBackendTest();
  }
  comicTranslationTest();
  comicOfflineTranslationTest();
  imageStripTransformTest();
  localRuleQuickJsHostTest();
  localRuleSourceFileImportTest();
  localBookImportTest();
  abilityTest();
  localRulePersistenceTest();
  localRuleBrowserIntegrationTest();
  sourcePlaybackSmokeTest();
  localRuleSourceBulkTesterTest();
  localRuleSourceRepositoryTest();
  localRuleTlsTrustTest();
  localRuleManagementIntegrationTest();
  localRuleBrowserLoginCoordinatorTests();
}
