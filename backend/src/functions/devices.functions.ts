// specs/001 §4.1 `POST /api/v1/devices`, §4.2 `GET /api/v1/devices`, §4.3
// `PATCH /api/v1/devices/{deviceId}`, §4.4 `DELETE /api/v1/devices/{deviceId}`. Thin: parse -> authenticate -> domain -> envelope.
// No business logic here (excluded from mutation, no unit tests — integration tests later).

import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from "@azure/functions";
import { randomUUID } from "node:crypto";
import { authenticate } from "../http/authGuard";
import { ok, fail } from "../http/envelope";
import { AppError } from "../http/errors";
import { toSafeErrorLog } from "../http/errorLogging";
import { deviceIdParamSchema, parseOrThrow } from "../http/validate";
import { registerDevice } from "../domain/device/registerDevice";
import { listMyDevices } from "../domain/device/listMyDevices";
import { patchDeviceSettings } from "../domain/device/patchDeviceSettings";
import { deleteDevice } from "../domain/device/deleteDevice";
import { createTokenVerifier } from "../adapters/auth/firebaseJoseVerifier";
import { TableUserRepo } from "../adapters/tables/usersTableRepo";
import { TableFamilyRepo } from "../adapters/tables/familiesTableRepo";
import { TableDeviceRepo } from "../adapters/tables/devicesTableRepo";
import { TableLastKnownRepo } from "../adapters/tables/lastKnownTableRepo";
import { TableIdempotencyRepo } from "../adapters/tables/idempotencyMarkersTableRepo";
import { TableEntitlementsRepo } from "../adapters/tables/entitlementsTableRepo";
import { TableUsageRepo } from "../adapters/tables/usageTableRepo";
import { FcmV1Sender } from "../adapters/push/fcmV1Sender";
import { SystemClock } from "../adapters/support/systemClock";

const tokenVerifier = createTokenVerifier();
const userRepo = new TableUserRepo();
const familyRepo = new TableFamilyRepo();
const deviceRepo = new TableDeviceRepo();
const entitlementsRepo = new TableEntitlementsRepo();
const lastKnownRepo = new TableLastKnownRepo();
const idempotencyRepo = new TableIdempotencyRepo();
const usageRepo = new TableUsageRepo();
const pushSender = new FcmV1Sender();
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

app.http("registerDevice", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "v1/devices",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const body: unknown = await request.json().catch(() => ({}));
      const result = await registerDevice(
        { uid: auth.uid, familyId: auth.familyId, body },
        { deviceRepo, familyRepo, entitlementsRepo, clock },
      );
      return {
        status: result.created ? 201 : 200,
        jsonBody: ok(result.device, result.features),
      };
    } catch (err) {
      return errorResponse(err, requestId, context, "registerDevice");
    }
  },
});

app.http("listMyDevices", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "v1/devices",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const result = await listMyDevices(
        { uid: auth.uid, familyId: auth.familyId },
        { deviceRepo, familyRepo, userRepo, entitlementsRepo, clock },
      );
      return { status: 200, jsonBody: ok({ devices: result.devices }, result.features) };
    } catch (err) {
      return errorResponse(err, requestId, context, "listMyDevices");
    }
  },
});

app.http("patchDeviceSettings", {
  methods: ["PATCH"],
  authLevel: "anonymous",
  route: "v1/devices/{deviceId}",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const { deviceId } = parseOrThrow(deviceIdParamSchema, { deviceId: request.params.deviceId });
      const body: unknown = await request.json().catch(() => ({}));
      const result = await patchDeviceSettings(
        { uid: auth.uid, familyId: auth.familyId, role: auth.role, deviceId, body },
        { deviceRepo, familyRepo, entitlementsRepo, pushSender },
      );
      return { status: 200, jsonBody: ok(result.device, result.features) };
    } catch (err) {
      return errorResponse(err, requestId, context, "patchDeviceSettings");
    }
  },
});

app.http("deleteDevice", {
  methods: ["DELETE"],
  authLevel: "anonymous",
  route: "v1/devices/{deviceId}",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const { deviceId } = parseOrThrow(deviceIdParamSchema, { deviceId: request.params.deviceId });
      await deleteDevice(
        { uid: auth.uid, familyId: auth.familyId, role: auth.role, deviceId },
        { deviceRepo, familyRepo, lastKnownRepo, idempotencyRepo },
      );
      return { status: 204 };
    } catch (err) {
      return errorResponse(err, requestId, context, "deleteDevice");
    }
  },
});
