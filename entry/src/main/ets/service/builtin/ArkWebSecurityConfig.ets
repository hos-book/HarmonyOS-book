import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlatformCompat } from '../../utils/PlatformCompat';

const DOMAIN: number = 0x0000;
const TAG: string = 'ArkWebSecurity';

let configured: boolean = false;

/**
 * Configures process-wide ArkWeb security before the first Web component initializes the engine.
 * Keep script/runtime features enabled because imported-source login pages can depend on site JavaScript.
 */
export function configureArkWebSecurity(): void {
  if (configured || !PlatformCompat.supports(26)) return;

  const securityParams: webview.SecurityParams = {
    disableJITCompilation: false,
    disableWebAssembly: false,
    disableWebGL: true,
    disablePDFViewer: true,
    disableMathML: true,
    disableServiceWorker: false,
    disableNonProxyUDP: true
  };

  try {
    webview.WebviewController.enableAdvancedSecurityMode(securityParams);
    configured = true;
    hilog.info(DOMAIN, TAG, 'ArkWeb advanced security mode configured');
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'ArkWeb security configuration failed: %{public}s', JSON.stringify(err));
  }
}
