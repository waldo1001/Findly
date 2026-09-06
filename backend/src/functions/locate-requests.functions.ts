// specs/001 §6.1 `POST /api/v1/locate-requests`, §6.2 `GET /api/v1/locate-requests/{requestId}`,
// §6.3 `POST /api/v1/locate-requests/{requestId}/fulfill`. Thin: parse -> authenticate ->
// domain -> envelope. No business logic here (excluded from mutation, no unit tests —
// integration tests later).

import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from "@azure/functions";
import { randomUUID } from "node:crypto";
import { authenticate } from "../http/authGuard";
import { ok, fail } from "../http/envelope";
import { AppError } from "../http/errors";
import { toSafeErrorLog } from "../http/errorLogging";
import { createLocateRequest } from "../domain/locate/createLocateRequest";
import { pollLocateRequest } from "../domain/locate/pollLocateRequest";
import { fulfillLocateRequest } from "../domain/locate/fulfillLocateRequest";
import { createTokenVerifier } from "../adapters/auth/firebaseJoseVerifier";
import { TableUserRepo } from "../adapters/tables/usersTableRepo";
import { TableFamilyRepo } from "../adapters/tables/familiesTableRepo";
import { TableDeviceRepo } from "../adapters/tables/devicesTableRepo";
import { TableLastKnownRepo } from "../adapters/tables/lastKnownTableRepo";
import { TableLocateRequestRepo } from "../adapters/tables/locateRequestsTableRepo";
import { TableIdempotencyRepo } from "../adapters/tables/idempotencyMarkersTableRepo";
import { TableEntitlementsRepo } from "../adapters/tables/entitlementsTableRepo";
import { TableUsageRepo } from "../adapters/tables/usageTableRepo";
import { BlobHistoryStore } from "../adapters/blobs/historyBlobStore";
import { FcmV1Sender } from "../adapters/push/fcmV1Sender";
import { SystemClock } from "../adapters/support/systemClock";
import { CryptoIdGenerator } from "../adapters/support/cryptoIdGenerator";

const tokenVerifier = createTokenVerifier();
const userRepo = new TableUserRepo();
const familyRepo = new TableFamilyRepo();
const deviceRepo = new TableDeviceRepo();
const lastKnownRepo = new TableLastKnownRepo();
const locateRequestRepo = new TableLocateRequestRepo();
const idempotencyRepo = new TableIdempotencyRepo();
const entitlementsRepo = new TableEntitlementsRepo();
const usageRepo = new TableUsageRepo();
const historyStore = new BlobHistoryStore();
const pushSender = new FcmV1Sender();
const clock = new SystemClock();
const idGenerator = new CryptoIdGenerator();

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

app.http("createLocateRequest", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "v1/locate-requests",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const body: unknown = await request.json().catch(() => ({}));
      const result = await createLocateRequest(
        { uid: auth.uid, familyId: auth.familyId, body },
        {
          deviceRepo,
          familyRepo,
          lastKnownRepo,
          locateRequestRepo,
          usageRepo,
          entitlementsRepo,
          pushSender,
          idGenerator,
          clock,
        },
      );
      return {
        status: result.created ? 201 : 200,
        jsonBody: ok(
          {
            requestId: result.requestId,
            status: result.status,
            targetUserId: result.targetUserId,
            targetDeviceId: result.targetDeviceId,
            createdAt: result.createdAt,
            expiresAt: result.expiresAt,
            lastKnown: result.lastKnown,
          },
          result.features,
        ),
      };
    } catch (err) {
      return errorResponse(err, requestId, context, "createLocateRequest");
    }
  },
});

app.http("pollLocateRequest", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "v1/locate-requests/{requestId}",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const result = await pollLocateRequest(
        { uid: auth.uid, familyId: auth.familyId, requestId: request.params.requestId ?? "" },
        { locateRequestRepo, entitlementsRepo, clock },
      );
      return {
        status: 200,
        jsonBody: ok(
          { requestId: result.requestId, status: result.status, expiresAt: result.expiresAt, fix: result.fix },
          result.features,
        ),
      };
    } catch (err) {
      return errorResponse(err, requestId, context, "pollLocateRequest");
    }
  },
});

app.http("fulfillLocateRequest", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "v1/locate-requests/{requestId}/fulfill",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const body: unknown = await request.json().catch(() => ({}));
      const result = await fulfillLocateRequest(
        {
          uid: auth.uid,
          deviceId: request.headers.get("x-device-id"),
          familyId: auth.familyId,
          requestId: request.params.requestId ?? "",
          body,
        },
        {
          deviceRepo,
          locateRequestRepo,
          lastKnownRepo,
          historyStore,
          idempotencyRepo,
          usageRepo,
          entitlementsRepo,
          clock,
        },
      );
      return { status: 200, jsonBody: ok({ status: result.status }, result.features) };
    } catch (err) {
      return errorResponse(err, requestId, context, "fulfillLocateRequest");
    }
  },
});
