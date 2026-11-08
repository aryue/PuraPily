// Input-zone coordinates are intentionally absent. Delta is a normalized level
// increment; velocity is normalized level increments per second. Sequence must
// change even when the displayed value is clamped at an endpoint.
export interface AdjustmentMotion {
  sequence: number;
  delta: number;
  velocity: number;
}
