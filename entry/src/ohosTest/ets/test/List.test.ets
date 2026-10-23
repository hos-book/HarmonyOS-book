import localBookImportTest from './LocalBookImport.test';
import imageStripTransformTest from './ImageStripTransform.test';
import localRuleQuickJsHostTest from './LocalRuleQuickJsHost.test';
import localRuleSourceFileImportTest from './LocalRuleSourceFileImport.test';
import abilityTest from './Ability.test';
import shuShanContentCryptoTest from './ShuShanContentCrypto.test';
import localRulePersistenceTest from './LocalRulePersistence.test';
import localRuleBrowserIntegrationTest from './LocalRuleBrowserIntegration.test';
import sourcePlaybackSmokeTest from './SourcePlaybackSmoke.test';
import localRuleSourceBulkTesterTest from '../../../test/LocalRuleSourceBulkTester.test';
import localRuleSourceRepositoryTest from '../../../test/LocalRuleSourceRepository.test';
import localRuleTlsTrustTest from '../../../test/LocalRuleTlsTrust.test';
import localRuleManagementIntegrationTest from './LocalRuleManagementIntegration.test';
import localRuleBrowserLoginCoordinatorTests from '../../../test/LocalRuleBrowserLoginCoordinator.test';

export default function testsuite() {
  imageStripTransformTest();
  localRuleQuickJsHostTest();
  localRuleSourceFileImportTest();
  localBookImportTest();
  abilityTest();
  shuShanContentCryptoTest();
  localRulePersistenceTest();
  localRuleBrowserIntegrationTest();
  sourcePlaybackSmokeTest();
  localRuleSourceBulkTesterTest();
  localRuleSourceRepositoryTest();
  localRuleTlsTrustTest();
  localRuleManagementIntegrationTest();
  localRuleBrowserLoginCoordinatorTests();
}
