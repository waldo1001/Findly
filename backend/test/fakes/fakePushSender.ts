import type { PushMessage, PushSendOutcome, PushSender } from "../../src/ports/pushSender";

/** Recording PushSender fake: captures every send() call, returns a configurable outcome. */
export class FakePushSender implements PushSender {
  readonly sent: PushMessage[] = [];
  private outcome: PushSendOutcome = "ok";
  private throwError: Error | null = null;

  /** Test control: subsequent send() calls resolve with this outcome (default "ok"). */
  setOutcome(outcome: PushSendOutcome): void {
    this.outcome = outcome;
  }

  /** Test control: simulates a THROWN transport-level failure (specs/001 §6.1 amended
   * 2026-09-06) — an OAuth exchange failure, a missing/malformed FCM_SERVICE_ACCOUNT_JSON,
   * or a rejected fetch — by making send() reject instead of resolving. An FCM 5xx does
   * NOT throw (src/adapters/push/fcmV1Sender.ts resolves it as outcome "error" instead) —
   * use setOutcome("error") to simulate that case. The real port's contract still says it
   * never throws for a rejected token, only for these genuine transport failures
   * (src/ports/pushSender.ts). */
  setThrows(error: Error): void {
    this.throwError = error;
  }

  async send(message: PushMessage): Promise<PushSendOutcome> {
    if (this.throwError) {
      throw this.throwError;
    }
    this.sent.push({ ...message, data: { ...message.data } });
    return this.outcome;
  }
}
