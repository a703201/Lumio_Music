import { Logger } from '../utils/Logger';
import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    Logger.info('onBackup ok');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    Logger.info('onRestore ok ' + (JSON.stringify(bundleVersion)));
    await Promise.resolve();
  }
}