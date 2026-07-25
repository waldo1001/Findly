// specs/001 §5.1 `POST /api/v1/locations`, §5.2 `GET /api/v1/locations/latest`. Thin:
// parse -> authenticate -> domain -> envelope. No business logic here (excluded from
// mutation, no unit tests — integration tests later).

import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from "@azure/functions";
import { randomUUID } from "node:crypto";
import { authenticate } from "../http/authGuard";
import { ok, fail } from "../http/envelope";
import { AppError } from "../http/errors";
import { toSafeErrorLog } from "../http/errorLogging";
import { reportLocations } from "../domain/location/reportLocations";
import { latestLocations } from "../domain/location/latestLocations";
import { createTokenVerifier } from "../adapters/auth/firebaseJoseVerifier";
import { TableUserRepo } from "../adapters/tables/usersTableRepo";
import { TableFamilyRepo } from "../adapters/tables/familiesTableRepo";
import { TableDeviceRepo } from "../adapters/tables/devicesTableRepo";
import { TableLastKnownRepo } from "../adapters/tables/lastKnownTableRepo";
import { TableIdempotencyRepo } from "../adapters/tables/idempotencyMarkersTableRepo";
import { TableEntitlementsRepo } from "../adapters/tables/entitlementsTableRepo";
import { TableUsageRepo } from "../adapters/tables/usageTableRepo";
import { TableGroupRepo } from "../adapters/tables/groupsTableRepo";
import { TableGroupLastKnownRepo } from "../adapters/tables/groupLastKnownTableRepo";
import { BlobHistoryStore } from "../adapters/blobs/historyBlobStore";
import { BlobGeofenceConfigRepo } from "../adapters/blobs/geofenceConfigBlobRepo";
import { SystemClock } from "../adapters/support/systemClock";

const tokenVerifier = createTokenVerifier();
const userRepo = new TableUserRepo();
const familyRepo = new TableFamilyRepo();
const deviceRepo = new TableDeviceRepo();
const lastKnownRepo = new TableLastKnownRepo();
const idempotencyRepo = new TableIdempotencyRepo();
const entitlementsRepo = new TableEntitlementsRepo();
const usageRepo = new TableUsageRepo();
const groupRepo = new TableGroupRepo();
const groupLastKnownRepo = new TableGroupLastKnownRepo();
const historyStore = new BlobHistoryStore();
const geofenceConfigRepo = new BlobGeofenceConfigRepo();
const clock = new SystemClock();

function newRequestId(): string {
  return `r_${randomUUID().replace(/-/g, "").slice(0, 16)}`;
}

function errorResponse(err: unknown, requestId: string, context: InvocationContext, label: string): HttpResponseInit {
  if (err instanceof AppError) {
    return { status: err.httpStatus, jsonBody: fail(err, requestId) };
  }
  context.error(`unhandled error in ${label}`, toSafeErrorLog(err));
  const internal = new AppError("INTERNAL_ERROR", "unexpected error");
  return { status: internal.httpStatus, jsonBody: fail(internal, requestId) };
}

app.http("reportLocations", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "v1/locations",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const body: unknown = await request.json().catch(() => ({}));
      const result = await reportLocations(
        {
          uid: auth.uid,
          familyId: auth.familyId,
          deviceId: request.headers.get("x-device-id"),
          body,
        },
        {
          deviceRepo,
          lastKnownRepo,
          idempotencyRepo,
          historyStore,
          usageRepo,
          geofenceConfigRepo,
          entitlementsRepo,
          userRepo,
          familyRepo,
          groupRepo,
          groupLastKnownRepo,
          clock,
        },
      );
      return {
        status: 200,
        jsonBody: ok(
          {
            accepted: result.accepted,
            duplicates: result.duplicates,
            lastKnownUpdated: result.lastKnownUpdated,
            deviceSettings: result.deviceSettings,
            geofenceEtag: result.geofenceEtag,
          },
          result.features,
        ),
      };
    } catch (err) {
      return errorResponse(err, requestId, context, "reportLocations");
    }
  },
});

app.http("latestLocations", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "v1/locations/latest",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const result = await latestLocations(
        { familyId: auth.familyId },
        { familyRepo, deviceRepo, lastKnownRepo, entitlementsRepo, clock },
      );
      return {
        status: 200,
        jsonBody: ok({ members: result.members }, result.features),
      };
    } catch (err) {
      return errorResponse(err, requestId, context, "latestLocations");
    }
  },
});
