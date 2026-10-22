import localBookImportTest from './LocalBookImport.test';
import localRuleQuickJsHostTest from './LocalRuleQuickJsHost.test';
import localRuleSourceFileImportTest from './LocalRuleSourceFileImport.test';
import abilityTest from './Ability.test';
import shuShanContentCryptoTest from './ShuShanContentCrypto.test';
import localRuleFeaturesTest from '../../../test/LocalRuleFeatures.test';
import localRuleRequestLimiterTest from '../../../test/LocalRuleRequestLimiter.test';
import localRuleCompatibilityTest from '../../../test/LocalRuleCompatibility.test';
import localRuleRuntimeTest from '../../../test/LocalRuleRuntime.test';
import localRulePersistenceTest from './LocalRulePersistence.test';
import localRuleBrowserIntegrationTest from './LocalRuleBrowserIntegration.test';
import sourcePlaybackSmokeTest from './SourcePlaybackSmoke.test';
import localRuleSourceBulkTesterTest from '../../../test/LocalRuleSourceBulkTester.test';
import localRuleSourceRepositoryTest from '../../../test/LocalRuleSourceRepository.test';
import localRuleTlsTrustTest from '../../../test/LocalRuleTlsTrust.test';
import localRuleManagementIntegrationTest from './LocalRuleManagementIntegration.test';
import localRuleBrowserLoginCoordinatorTests from '../../../test/LocalRuleBrowserLoginCoordinator.test';

export default function testsuite() {
  localRuleQuickJsHostTest();
  localRuleSourceFileImportTest();
  localBookImportTest();
  abilityTest();
  shuShanContentCryptoTest();
  localRuleFeaturesTest();
  localRuleRequestLimiterTest();
  localRuleCompatibilityTest();
  localRuleRuntimeTest();
  localRulePersistenceTest();
  localRuleBrowserIntegrationTest();
  sourcePlaybackSmokeTest();
  localRuleSourceBulkTesterTest();
  localRuleSourceRepositoryTest();
  localRuleTlsTrustTest();
  localRuleManagementIntegrationTest();
  localRuleBrowserLoginCoordinatorTests();
}
