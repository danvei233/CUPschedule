import { FlutterEngine, Log } from '@ohos/flutter_ohos';
import SharedPreferencesOhosPlugin from 'shared_preferences_ohos';

const TAG = 'GeneratedPluginRegistrant';

export class GeneratedPluginRegistrant {
  static registerWith(flutterEngine: FlutterEngine) {
    try {
      flutterEngine.getPlugins()?.add(new SharedPreferencesOhosPlugin());
    } catch (e) {
      Log.e(TAG, 'Tried to register plugins with FlutterEngine (' + flutterEngine + ') failed.');
      Log.e(TAG, 'Received exception while registering', e);
    }
  }
}
