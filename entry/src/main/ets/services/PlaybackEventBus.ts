import { media } from '@kit.MediaKit';

/** Adapts the SDK's overloaded event API to an owned set of subscriptions. */
export class PlaybackEventBus {
  private listeners = new Map<string, Set<Function>>();

  readonly on: media.AVPlayer['on'] = (event: string, callback: Function | number[], _sei?: Function): void => {
    if (typeof callback !== 'function') throw new Error('IJK SEI subscriptions are unsupported');
    let subscriptions = this.listeners.get(event);
    if (!subscriptions) {
      subscriptions = new Set<Function>();
      this.listeners.set(event, subscriptions);
    }
    subscriptions.add(callback);
  };

  readonly off: media.AVPlayer['off'] = (event: string, callback?: Function | number[], _sei?: Function): void => {
    if (typeof callback === 'function') this.listeners.get(event)?.delete(callback);
    else if (!callback) this.listeners.delete(event);
  };

  emit(event: string, ...values: Object[]): void {
    Array.from(this.listeners.get(event) || []).forEach(callback => callback(...values));
  }

  clear(): void { this.listeners.clear(); }
}
