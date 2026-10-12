// specs/001 §12.1 `POST /api/v1/groups`, §12.2 `GET /api/v1/groups`, §12.3
// `GET /api/v1/groups/{groupId}`, §12.4 `PATCH /api/v1/groups/{groupId}`, §12.5
// `DELETE /api/v1/groups/{groupId}`, §12.6 `POST /api/v1/groups/join`, §12.7
// `POST /api/v1/groups/{groupId}/code/rotate`, §12.8 `POST /api/v1/groups/{groupId}/leave`,
// §12.9 `DELETE /api/v1/groups/{groupId}/members/{userId}`, §12.10
// `GET /api/v1/groups/{groupId}/locations/latest`. Thin: parse -> authenticate -> domain ->
// envelope. No business logic here (excluded from mutation, no unit tests — integration
// tests later).

import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from "@azure/functions";
import { randomUUID } from "node:crypto";
import { authenticate } from "../http/authGuard";
import { ok, fail } from "../http/envelope";
import { AppError } from "../http/errors";
import { toSafeErrorLog } from "../http/errorLogging";
import { groupIdParamSchema, memberUserIdParamSchema, parseOrThrow } from "../http/validate";
import { createGroup } from "../domain/group/createGroup";
import { listGroups } from "../domain/group/listGroups";
import { getGroupDetail } from "../domain/group/getGroupDetail";
import { joinGroup } from "../domain/group/joinGroup";
import { patchGroup } from "../domain/group/patchGroup";
import { deleteGroup } from "../domain/group/deleteGroup";
import { rotateGroupCode } from "../domain/group/rotateGroupCode";
import { leaveGroup } from "../domain/group/leaveGroup";
import { kickMember } from "../domain/group/kickMember";
import { getGroupLatestLocations } from "../domain/group/getGroupLatestLocations";
import { createTokenVerifier } from "../adapters/auth/firebaseJoseVerifier";
import { TableUserRepo } from "../adapters/tables/usersTableRepo";
import { TableGroupRepo } from "../adapters/tables/groupsTableRepo";
import { TableGroupCodeRepo } from "../adapters/tables/groupCodesTableRepo";
import { TableGroupExpiryRepo } from "../adapters/tables/groupExpiryTableRepo";
import { TableGroupLastKnownRepo } from "../adapters/tables/groupLastKnownTableRepo";
import { TableEntitlementsRepo } from "../adapters/tables/entitlementsTableRepo";
import { TableUsageRepo } from "../adapters/tables/usageTableRepo";
import { SystemClock } from "../adapters/support/systemClock";
import { CryptoIdGenerator } from "../adapters/support/cryptoIdGenerator";
import { CryptoInviteCodeGenerator } from "../adapters/support/cryptoInviteCodeGenerator";

const tokenVerifier = createTokenVerifier();
const userRepo = new TableUserRepo();
const groupRepo = new TableGroupRepo();
const groupCodeRepo = new TableGroupCodeRepo();
const groupExpiryRepo = new TableGroupExpiryRepo();
const groupLastKnownRepo = new TableGroupLastKnownRepo();
const entitlementsRepo = new TableEntitlementsRepo();
const usageRepo = new TableUsageRepo();
const clock = new SystemClock();
const idGenerator = new CryptoIdGenerator();
// Same 8-char Crockford format/normalization as family invite codes (005 §1, 001 §1.4).
const inviteCodeGenerator = new CryptoInviteCodeGenerator();

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

app.http("createGroup", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "v1/groups",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(
        request.headers.get("authorization"),
        { tokenVerifier, userRepo, usageRepo, clock },
        { allowNoProfile: true },
      );
      const body: unknown = await request.json().catch(() => ({}));
      const result = await createGroup(
        { uid: auth.uid, body },
        { groupRepo, groupCodeRepo, groupExpiryRepo, userRepo, entitlementsRepo, idGenerator, inviteCodeGenerator, clock },
      );
      const { features, ...data } = result;
      return { status: 201, jsonBody: ok(data, features) };
    } catch (err) {
      return errorResponse(err, requestId, context, "createGroup");
    }
  },
});

app.http("listGroups", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "v1/groups",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const result = await listGroups(
        { uid: auth.uid, familyId: auth.familyId },
        { groupRepo, userRepo, entitlementsRepo, clock },
      );
      return { status: 200, jsonBody: ok({ groups: result.groups }, result.features) };
    } catch (err) {
      return errorResponse(err, requestId, context, "listGroups");
    }
  },
});

app.http("getGroupDetail", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "v1/groups/{groupId}",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const { groupId } = parseOrThrow(groupIdParamSchema, { groupId: request.params.groupId });
      const result = await getGroupDetail(
        { uid: auth.uid, familyId: auth.familyId, groupId },
        { groupRepo, entitlementsRepo, clock },
      );
      const { features, ...data } = result;
      return { status: 200, jsonBody: ok(data, features) };
    } catch (err) {
      return errorResponse(err, requestId, context, "getGroupDetail");
    }
  },
});

app.http("joinGroup", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "v1/groups/join",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(
        request.headers.get("authorization"),
        { tokenVerifier, userRepo, usageRepo, clock },
        { allowNoProfile: true },
      );
      const body: unknown = await request.json().catch(() => ({}));
      const result = await joinGroup(
        { uid: auth.uid, body },
        { groupRepo, groupCodeRepo, userRepo, entitlementsRepo, clock },
      );
      const { features, ...data } = result;
      return { status: 200, jsonBody: ok(data, features) };
    } catch (err) {
      return errorResponse(err, requestId, context, "joinGroup");
    }
  },
});

app.http("patchGroup", {
  methods: ["PATCH"],
  authLevel: "anonymous",
  route: "v1/groups/{groupId}",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const { groupId } = parseOrThrow(groupIdParamSchema, { groupId: request.params.groupId });
      const body: unknown = await request.json().catch(() => ({}));
      const result = await patchGroup(
        { uid: auth.uid, familyId: auth.familyId, groupId, body },
        { groupRepo, groupExpiryRepo, userRepo, entitlementsRepo, clock },
      );
      const { features, ...data } = result;
      return { status: 200, jsonBody: ok(data, features) };
    } catch (err) {
      return errorResponse(err, requestId, context, "patchGroup");
    }
  },
});

app.http("deleteGroup", {
  methods: ["DELETE"],
  authLevel: "anonymous",
  route: "v1/groups/{groupId}",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const { groupId } = parseOrThrow(groupIdParamSchema, { groupId: request.params.groupId });
      await deleteGroup(
        { uid: auth.uid, familyId: auth.familyId, groupId },
        { groupRepo, groupCodeRepo, groupExpiryRepo, groupLastKnownRepo, userRepo },
      );
      return { status: 204 };
    } catch (err) {
      return errorResponse(err, requestId, context, "deleteGroup");
    }
  },
});

app.http("rotateGroupCode", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "v1/groups/{groupId}/code/rotate",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const { groupId } = parseOrThrow(groupIdParamSchema, { groupId: request.params.groupId });
      const result = await rotateGroupCode(
        { uid: auth.uid, familyId: auth.familyId, groupId },
        { groupRepo, groupCodeRepo, entitlementsRepo, inviteCodeGenerator, clock },
      );
      const { features, ...data } = result;
      return { status: 200, jsonBody: ok(data, features) };
    } catch (err) {
      return errorResponse(err, requestId, context, "rotateGroupCode");
    }
  },
});

app.http("leaveGroup", {
  methods: ["POST"],
  authLevel: "anonymous",
  route: "v1/groups/{groupId}/leave",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const { groupId } = parseOrThrow(groupIdParamSchema, { groupId: request.params.groupId });
      await leaveGroup(
        { uid: auth.uid, familyId: auth.familyId, groupId },
        { groupRepo, groupLastKnownRepo, userRepo, entitlementsRepo, clock },
      );
      return { status: 204 };
    } catch (err) {
      return errorResponse(err, requestId, context, "leaveGroup");
    }
  },
});

app.http("kickMember", {
  methods: ["DELETE"],
  authLevel: "anonymous",
  route: "v1/groups/{groupId}/members/{userId}",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const { groupId } = parseOrThrow(groupIdParamSchema, { groupId: request.params.groupId });
      const { userId: targetUserId } = parseOrThrow(memberUserIdParamSchema, { userId: request.params.userId });
      await kickMember(
        { uid: auth.uid, familyId: auth.familyId, groupId, targetUserId },
        { groupRepo, groupLastKnownRepo, userRepo, entitlementsRepo, clock },
      );
      return { status: 204 };
    } catch (err) {
      return errorResponse(err, requestId, context, "kickMember");
    }
  },
});

app.http("getGroupLatestLocations", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "v1/groups/{groupId}/locations/latest",
  handler: async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    const requestId = newRequestId();
    try {
      const auth = await authenticate(request.headers.get("authorization"), { tokenVerifier, userRepo, usageRepo, clock });
      const { groupId } = parseOrThrow(groupIdParamSchema, { groupId: request.params.groupId });
      const result = await getGroupLatestLocations(
        { uid: auth.uid, familyId: auth.familyId, groupId },
        { groupRepo, groupLastKnownRepo, entitlementsRepo, clock },
      );
      return { status: 200, jsonBody: ok({ members: result.members }, result.features) };
    } catch (err) {
      return errorResponse(err, requestId, context, "getGroupLatestLocations");
    }
  },
});
