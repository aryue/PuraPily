import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface PrefetchRoute {
  local: boolean;
  wifi: boolean;
  metered: boolean;
  stable: boolean;
  /** Bearer types were reported; an empty capability set is still an unknown route. */
  known: boolean;
  /** Settings toggle (or --ps cellularPrefetch on) permitting cellular/metered prewarming. */
  cellularOverride: boolean;
}

/** Read the actual route each time; never carry Wi-Fi permission across a route change. */
export class NetworkGate {
  private static lastDecision: string = '';

  private static record(decision: string): void {
    if (decision === NetworkGate.lastDecision) return;
    NetworkGate.lastDecision = decision;
    hilog.info(0, 'NetworkGate', 'prefetch policy %{public}s', decision);
  }

  private static route(): PrefetchRoute | null {
    try {
      const handle = connection.getDefaultNetSync();
      if (!handle || handle.netId === 0) { NetworkGate.record('unknown-route'); return null; }
      const caps = connection.getNetCapabilitiesSync(handle);
      const bearers = caps.bearerTypes || [];
      const wifi = bearers.includes(connection.NetBearType.BEARER_WIFI);
      const ethernet = bearers.includes(connection.NetBearType.BEARER_ETHERNET);
      const cellular = bearers.includes(connection.NetBearType.BEARER_CELLULAR);
      const metered = connection.isDefaultNetMeteredSync() !== false;
      const current = connection.getDefaultNetSync();
      const stable = current.netId === handle.netId;
      const local = (wifi || ethernet) && !cellular;
      const known = bearers.length > 0;
      // Read on every call so the settings toggle and `aa start --ps cellularPrefetch on|off` take effect live.
      const cellularOverride = AppStorage.get<boolean>('cellularPrefetch') === true;
      NetworkGate.record(`bounded=${local && stable && (wifi || !metered)} policyMetered=${metered} ` +
        `cellular=${cellular ? 1 : 0} override=${cellularOverride ? 1 : 0} bearers=${JSON.stringify(bearers)}`);
      return {
        local: local, wifi: wifi, metered: metered, stable: stable,
        known: known, cellularOverride: cellularOverride
      };
    } catch (_) {
      NetworkGate.record('query-failed');
      return null;
    }
  }

  /** Unbounded/decoder experiments still require an explicitly unmetered local network. */
  static isMetered(): boolean {
    const route = NetworkGate.route();
    if (route === null) return true;
    // Override: a known, stable route (including cellular) is treated as permitted.
    if (route.cellularOverride && route.known && route.stable) return false;
    return !route.local || !route.stable || route.metered;
  }

  /** User permits bounded prefixes on metered Wi-Fi; cellular/unknown remain blocked by default. */
  static allowsBoundedPrefix(): boolean {
    const route = NetworkGate.route();
    if (route === null) return false;
    // Override: cellular/metered routes pass, unknown or switching routes still deny.
    if (route.cellularOverride && route.known && route.stable) return true;
    return route.local && route.stable && (route.wifi || !route.metered);
  }
}
