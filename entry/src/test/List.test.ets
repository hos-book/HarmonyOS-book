import localUnitTest from './LocalUnit.test';
import downloadPolicyTest from './DownloadPolicy.test';
import asyncSingleFlightTest from './AsyncSingleFlight.test';
import searchCacheTest from './SearchCache.test';
import listeningHistoryPolicyTest from './ListeningHistoryPolicy.test';
import chapterProgressPolicyTest from './ChapterProgressPolicy.test';
import onlineTextPaginatorTest from './OnlineTextPaginator.test';
import localRuleSourceBulkTesterTest from './LocalRuleSourceBulkTester.test';
import localRuleTlsTrustTest from './LocalRuleTlsTrust.test';
import localRuleBrowserLoginCoordinatorTests from './LocalRuleBrowserLoginCoordinator.test';
import localRuleSourceRepositoryTest from './LocalRuleSourceRepository.test';
import readerThemeTest from './ReaderTheme.test';
import searchHistoryTest from './SearchHistory.test';

export default function testsuite() {
  localUnitTest();
  downloadPolicyTest();
  asyncSingleFlightTest();
  searchCacheTest();
  listeningHistoryPolicyTest();
  chapterProgressPolicyTest();
  onlineTextPaginatorTest();
  localRuleSourceBulkTesterTest();
  localRuleTlsTrustTest();
  localRuleBrowserLoginCoordinatorTests();
  localRuleSourceRepositoryTest();
  readerThemeTest();
  searchHistoryTest();
}
