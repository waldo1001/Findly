// specs/001 §13.2 `DELETE /api/v1/users/me` (specs/008 §4). Thin: authenticate -> domain ->
// bare 204. No business logic here (excluded from mutation, no unit tests — integration
// tests later). Available WITHOUT a profile (`allowNoProfile: true`, 001 §1.5.3) — the one
// endpoint besides the four bootstrap ones the auth guard admits with no Users row at all.

import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from "@azure/functions";
import { randomUUID } from "node:crypto";
import { authenticate } from "../http/authGuard";
import { fail } from "../http/envelope";
import { AppError } from "../http/errors";
import { toSafeErrorLog } from "../http/errorLogging";
import { deleteAccount } from "../domain/user/deleteAccount";
import { createTokenVerifier } from "../adapters/auth/firebaseJoseVerifier";
import { TableUserRepo } from "../adapters/tables/usersTableRepo";
import { TableFamilyRepo } from "../adapters/tables/familiesTableRepo";
import { TableEntitlementsRepo } from "../adapters/tables/entitlementsTableRepo";
import { TableUsageRepo } from "../adapters/tables/usageTableRepo";
import { TableDeviceRepo } from "../adapters/tables/devicesTableRepo";
import { TableLastKnownRepo } from "../adapters/tables/lastKnownTableRepo";
import { TableIdempotencyRepo } from "../adapters/tables/idempotencyMarkersTableRepo";
import { TableInviteRepo } from "../adapters/tables/invitesTableRepo";
import { TableLocateRequestRepo } from "../adapters/tables/locateRequestsTableRepo";
import { TableGroupRepo } from "../adapters/tables/groupsTableRepo";
import { TableGroupCodeRepo } from "../adapters/tables/groupCodesTableRepo";
import { TableGroupLastKnownRepo } from "../adapters/tables/groupLastKnownTableRepo";
import { TableGroupExpiryRepo } from "../adapters/tables/groupExpiryTableRepo";
import { BlobHistoryStore } from "../adapters/blobs/historyBlobStore";
import { BlobGeofenceConfigRepo } from "../adapters/blobs/geofenceConfigBlobRepo";
import { SystemClock } from "../adapters/support/systemClock";

const tokenVerifier = createTokenVerifier();
const userRepo = new TableUserRepo();
const familyRepo = new TableFamilyRepo();
const entitlementsRepo = new TableEntitlementsRepo();
const usageRepo = new TableUsageRepo();
const deviceRepo = new TableDeviceRepo();
const lastKnownRepo = new TableLastKnownRepo();
const idempotencyRepo = new TableIdempotencyRepo();
const inviteRepo = new TableInviteRepo();
const locateRequestRepo = new TableLocateRequestRepo();
const groupRepo = new TableGroupRepo();
const groupCodeRepo = new TableGroupCodeRepo();
const groupLastKnownRepo = new TableGroupLastKnownRepo();
const groupExpiryRepo = new TableGroupExpiryRepo();
const historyStore = new BlobHistoryStore();
const geofenceConfigRepo = new BlobGeofenceConfigRepo();
const clock = new SystemClock();

function newRequestId(): string {
  return `r_${randomUUID().replace(/-/g, "").slice(0, 16)}`;
}

app.http("deleteAccount", {
  methods: ["DELETE"],
  authLevel: "anonymous",
  route: "v1/users/me",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(
        request.headers.get("authorization"),
        { tokenVerifier, userRepo, usageRepo, clock },
        { allowNoProfile: true },
      );
      await deleteAccount(
        { uid: auth.uid, familyId: auth.familyId },
        {
          familyRepo,
          userRepo,
          inviteRepo,
          entitlementsRepo,
          usageRepo,
          locateRequestRepo,
          historyStore,
          geofenceConfigRepo,
          deviceRepo,
          lastKnownRepo,
          idempotencyRepo,
          groupRepo,
          groupCodeRepo,
          groupLastKnownRepo,
          groupExpiryRepo,
        },
      );
      return { status: 204 };
    } catch (err) {
      if (err instanceof AppError) {
        return { status: err.httpStatus, jsonBody: fail(err, requestId) };
      }
      context.error("unhandled error in deleteAccount", toSafeErrorLog(err));
      const internal = new AppError("INTERNAL_ERROR", "unexpected error");
      return { status: internal.httpStatus, jsonBody: fail(internal, requestId) };
    }
  },
});
