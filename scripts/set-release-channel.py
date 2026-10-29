"""Set the packaged entry points and app version before building a release channel."""
import argparse
from pathlib import Path
import re


def replace_once(text: str, pattern: str, value: str) -> str:
    result, count = re.subn(pattern, lambda _: value, text)
    if count != 1:
        raise ValueError(f'Expected one match for {pattern}, got {count}')
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--channel', choices=['device', 'invite', 'release'], required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--version-code', type=int, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version) or args.version_code <= 0:
        parser.error('Use a three-part version and a positive version code')
    root = Path(__file__).resolve().parents[1]
    policy_path = root / 'entry/src/main/ets/utils/ReleasePolicy.ets'
    version_path = root / 'AppScope/app.json5'
    policy = policy_path.read_text(encoding='utf-8')
    for key, enabled in [('showPodcastEntry', args.channel == 'device'),
                         ('membershipPurchaseEnabled', args.channel == 'release')]:
        policy = replace_once(policy, rf'{key}: boolean = (?:true|false);',
                              f'{key}: boolean = {str(enabled).lower()};')
    version = version_path.read_text(encoding='utf-8')
    version = replace_once(version, r'"versionCode":\s*\d+', f'"versionCode": {args.version_code}')
    version = replace_once(version, r'"versionName":\s*"[^"]+"', f'"versionName": "{args.version}"')
    policy_path.write_text(policy, encoding='utf-8')
    version_path.write_text(version, encoding='utf-8')
    print(f'channel={args.channel}, version={args.version}, versionCode={args.version_code}')


if __name__ == '__main__':
    main()
