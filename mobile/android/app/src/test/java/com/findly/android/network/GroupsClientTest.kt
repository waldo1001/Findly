package com.findly.android.network

import com.findly.android.fakes.FakeAuthProvider
import com.findly.android.network.dto.UpdateGroupRequestDto
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * `GroupsApi` request-building against the real Retrofit/OkHttp/kotlinx.serialization stack via a
 * local [MockWebServer] (specs/003-android-client.md §5's endpoint table, §14, §16's "GroupsApi
 * request-building per §5 row (routes, bare-204 handling on §12.5/12.8/12.9)"). Covers every one
 * of 001-api-contract.md §12's 10 group endpoints.
 */
class GroupsClientTest {

    private lateinit var server: MockWebServer
    private lateinit var authProvider: FakeAuthProvider
    private lateinit var client: FindlyApiClient

    private val featuresJson = """
        "features":{"subscriptionStatus":"free",
          "limits":{"maxDevices":10,"maxGeofences":20,"historyDays":90,
                    "minSyncIntervalMinutes":5,"locateRequestsPerDay":100},
          "flags":{"pushToLocate":true,"geofencing":true,"historyReplay":true}}
    """.trimIndent()

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        authProvider = FakeAuthProvider()
        val service = RetrofitFactory.create(server.url("/").toString(), authProvider)
        client = FindlyApiClient(service, authProvider)
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    // ------------------------------------------------------------------
    // 12.1 Create group
    // ------------------------------------------------------------------

    @Test
    fun `createGroup POSTs v1_groups and unwraps the 201 response`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(201).setBody(
                """
                {"data":{"groupId":"grp_9J2Kq7Lm3NpR5sTvWxYz","name":"Festival crew",
                          "endsAt":"2026-08-02T22:00:00Z","expiryPolicy":"delete","state":"active",
                          "role":"owner","memberCount":1,"code":"7F3K9QRZ",
                          "createdAt":"2026-07-21T10:00:00Z"},
                 $featuresJson}
                """.trimIndent(),
            ),
        )

        val result = client.createGroup(
            name = "Festival crew",
            endsAt = "2026-08-02T22:00:00Z",
            expiryPolicy = "delete",
            displayName = "Eric",
        )

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals("grp_9J2Kq7Lm3NpR5sTvWxYz", result.data.groupId)
        assertEquals("owner", result.data.role)
        assertEquals("active", result.data.state)
        assertEquals(1, result.data.memberCount)
        assertEquals("7F3K9QRZ", result.data.code)
        assertEquals("2026-07-21T10:00:00Z", result.data.createdAt)

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/v1/groups", recorded.path)
        assertTrue(recorded.body.readUtf8().contains("\"displayName\":\"Eric\""))
    }

    @Test
    fun `createGroup omits displayName from the request body when not supplied (optional-otherwise, 001 §12_1)`() =
        runTest {
            server.enqueue(
                MockResponse().setResponseCode(201).setBody(
                    """
                    {"data":{"groupId":"grp_1","name":"Festival crew","endsAt":"2026-08-02T22:00:00Z",
                              "expiryPolicy":"delete","state":"active","role":"owner","memberCount":1,
                              "code":"7F3K9QRZ","createdAt":"2026-07-21T10:00:00Z"},
                     $featuresJson}
                    """.trimIndent(),
                ),
            )

            client.createGroup(name = "Festival crew", endsAt = "2026-08-02T22:00:00Z", expiryPolicy = "delete")

            val recorded = server.takeRequest()
            assertTrue(!recorded.body.readUtf8().contains("displayName"))
        }

    // ------------------------------------------------------------------
    // 12.2 List my groups
    // ------------------------------------------------------------------

    @Test
    fun `listGroups GETs v1_groups and unwraps each item, including a null code past endsAt`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """
                {"data":{"groups":[
                    {"groupId":"grp_1","name":"Festival crew","endsAt":"2026-08-02T22:00:00Z",
                     "expiryPolicy":"delete","state":"active","role":"owner","memberCount":7,
                     "code":"7F3K9QRZ"},
                    {"groupId":"grp_2","name":"Old trip","endsAt":"2026-01-01T00:00:00Z",
                     "expiryPolicy":"archive","state":"archived","role":"member","memberCount":3,
                     "code":null}
                 ]},
                 $featuresJson}
                """.trimIndent(),
            ),
        )

        val result = client.listGroups()

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(2, result.data.groups.size)
        assertEquals("7F3K9QRZ", result.data.groups[0].code)
        assertNull(result.data.groups[1].code)
        assertEquals("archived", result.data.groups[1].state)

        val recorded = server.takeRequest()
        assertEquals("GET", recorded.method)
        assertEquals("/v1/groups", recorded.path)
    }

    // ------------------------------------------------------------------
    // 12.3 Get group
    // ------------------------------------------------------------------

    @Test
    fun `getGroup returns the full roster for the owner`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """
                {"data":{"groupId":"grp_1","name":"Festival crew","endsAt":"2026-08-02T22:00:00Z",
                          "expiryPolicy":"delete","state":"active","role":"owner","memberCount":2,
                          "code":"7F3K9QRZ","createdAt":"2026-07-21T10:00:00Z",
                          "members":[
                            {"userId":"u1","displayName":"Eric","role":"owner",
                             "joinedAt":"2026-07-21T10:00:00Z"},
                            {"userId":"u9","displayName":"Noor","role":"member",
                             "joinedAt":"2026-07-21T10:05:00Z"}]},
                 $featuresJson}
                """.trimIndent(),
            ),
        )

        val result = client.getGroup("grp_1")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(2, result.data.members?.size)
        assertEquals("Eric", result.data.members?.get(0)?.displayName)

        val recorded = server.takeRequest()
        assertEquals("GET", recorded.method)
        assertEquals("/v1/groups/grp_1", recorded.path)
    }

    @Test
    fun `getGroup hides the roster (members null) for a non-owner during grace`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """
                {"data":{"groupId":"grp_1","name":"Festival crew","endsAt":"2026-07-20T10:00:00Z",
                          "expiryPolicy":"delete","state":"ended","role":"member","memberCount":2,
                          "code":null,"createdAt":"2026-07-19T10:00:00Z","members":null},
                 $featuresJson}
                """.trimIndent(),
            ),
        )

        val result = client.getGroup("grp_1")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertNull(result.data.members)
        assertEquals("ended", result.data.state)
        assertNull(result.data.code)
    }

    // ------------------------------------------------------------------
    // 12.4 Update group
    // ------------------------------------------------------------------

    @Test
    fun `updateGroup PATCHes v1_groups_{groupId} and unwraps a createdAt-less GroupDto`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """
                {"data":{"groupId":"grp_1","name":"Festival crew 2026","endsAt":"2026-08-03T22:00:00Z",
                          "expiryPolicy":"delete","state":"active","role":"owner","memberCount":7,
                          "code":"7F3K9QRZ"},
                 $featuresJson}
                """.trimIndent(),
            ),
        )

        val result = client.updateGroup(
            "grp_1",
            UpdateGroupRequestDto(name = "Festival crew 2026", endsAt = "2026-08-03T22:00:00Z"),
        )

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals("Festival crew 2026", result.data.name)
        assertNull(result.data.createdAt)

        val recorded = server.takeRequest()
        assertEquals("PATCH", recorded.method)
        assertEquals("/v1/groups/grp_1", recorded.path)
    }

    // ------------------------------------------------------------------
    // 12.5 Delete group
    // ------------------------------------------------------------------

    @Test
    fun `deleteGroup DELETEs v1_groups_{groupId} and yields Success(Unit, features = null) on 204`() = runTest {
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.deleteGroup("grp_1")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(Unit, result.data)
        assertNull(result.features)

        val recorded = server.takeRequest()
        assertEquals("DELETE", recorded.method)
        assertEquals("/v1/groups/grp_1", recorded.path)
    }

    // ------------------------------------------------------------------
    // 12.6 Join group
    // ------------------------------------------------------------------

    @Test
    fun `joinGroup POSTs v1_groups_join and unwraps the 200 response`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """
                {"data":{"groupId":"grp_1","name":"Festival crew","endsAt":"2026-08-02T22:00:00Z",
                          "expiryPolicy":"delete","state":"active","role":"member","memberCount":8,
                          "code":"7F3K9QRZ"},
                 $featuresJson}
                """.trimIndent(),
            ),
        )

        val result = client.joinGroup(code = "7f3k-9qrz", displayName = "Noor")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals("member", result.data.role)
        assertEquals(8, result.data.memberCount)

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/v1/groups/join", recorded.path)
    }

    @Test
    fun `joinGroup surfaces GROUP_CODE_INVALID, GROUP_ALREADY_MEMBER, GROUP_FULL, and GROUP_EXPIRED`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(400).setBody(
                """{"error":{"code":"GROUP_CODE_INVALID","message":"unknown code","requestId":"r_j1"}}""",
            ),
        )
        val invalid = client.joinGroup("BADCODE1")
        assertTrue((invalid as ApiResult.Failure).error is ApiError.GroupCodeInvalid)

        server.enqueue(
            MockResponse().setResponseCode(409).setBody(
                """{"error":{"code":"GROUP_ALREADY_MEMBER","message":"already in","requestId":"r_j2"}}""",
            ),
        )
        val alreadyMember = client.joinGroup("7F3K9QRZ")
        assertTrue((alreadyMember as ApiResult.Failure).error is ApiError.GroupAlreadyMember)

        server.enqueue(
            MockResponse().setResponseCode(409).setBody(
                """{"error":{"code":"GROUP_FULL","message":"full","details":{"max":50},"requestId":"r_j3"}}""",
            ),
        )
        val full = client.joinGroup("7F3K9QRZ")
        val fullError = (full as ApiResult.Failure).error
        assertTrue(fullError is ApiError.GroupFull)
        assertEquals(50, (fullError as ApiError.GroupFull).max)

        server.enqueue(
            MockResponse().setResponseCode(410).setBody(
                """{"error":{"code":"GROUP_EXPIRED","message":"ended","requestId":"r_j4"}}""",
            ),
        )
        val expired = client.joinGroup("7F3K9QRZ")
        assertTrue((expired as ApiResult.Failure).error is ApiError.GroupExpired)
    }

    // ------------------------------------------------------------------
    // 12.7 Rotate join code
    // ------------------------------------------------------------------

    @Test
    fun `rotateGroupCode POSTs v1_groups_{groupId}_code_rotate and unwraps the new code`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"data":{"code":"9XPT4WKA","rotatedAt":"2026-07-21T10:05:00Z"}, $featuresJson}""",
            ),
        )

        val result = client.rotateGroupCode("grp_1")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals("9XPT4WKA", result.data.code)
        assertEquals("2026-07-21T10:05:00Z", result.data.rotatedAt)

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/v1/groups/grp_1/code/rotate", recorded.path)
    }

    // ------------------------------------------------------------------
    // 12.8 Leave group
    // ------------------------------------------------------------------

    @Test
    fun `leaveGroup POSTs v1_groups_{groupId}_leave and yields Success(Unit, features = null) on 204`() = runTest {
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.leaveGroup("grp_1")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(Unit, result.data)
        assertNull(result.features)

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/v1/groups/grp_1/leave", recorded.path)
    }

    @Test
    fun `leaveGroup surfaces the owner-cannot-leave VALIDATION_FAILED reason`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(400).setBody(
                """{"error":{"code":"VALIDATION_FAILED","message":"owner cannot leave",
                             "details":{"reason":"ownerCannotLeave"},"requestId":"r_l1"}}""",
            ),
        )

        val result = client.leaveGroup("grp_1")

        assertTrue(result is ApiResult.Failure)
        val error = (result as ApiResult.Failure).error
        assertTrue(error is ApiError.ValidationFailed)
        assertEquals("ownerCannotLeave", (error as ApiError.ValidationFailed).reason)
    }

    // ------------------------------------------------------------------
    // 12.9 Kick member
    // ------------------------------------------------------------------

    @Test
    fun `removeGroupMember DELETEs v1_groups_{groupId}_members_{userId} and yields Success on 204`() = runTest {
        server.enqueue(MockResponse().setResponseCode(204))

        val result = client.removeGroupMember("grp_1", "u9")

        assertTrue(result is ApiResult.Success)
        result as ApiResult.Success
        assertEquals(Unit, result.data)
        assertNull(result.features)

        val recorded = server.takeRequest()
        assertEquals("DELETE", recorded.method)
        assertEquals("/v1/groups/grp_1/members/u9", recorded.path)
    }

    @Test
    fun `removeGroupMember surfaces MEMBER_NOT_FOUND for an unknown userId`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(404).setBody(
                """{"error":{"code":"MEMBER_NOT_FOUND","message":"no such member","requestId":"r_m1"}}""",
            ),
        )

        val result = client.removeGroupMember("grp_1", "ghost")

        assertTrue(result is ApiResult.Failure)
        assertTrue((result as ApiResult.Failure).error is ApiError.MemberNotFound)
    }

    // ------------------------------------------------------------------
    // 12.10 Group live map
    // ------------------------------------------------------------------

    @Test
    fun `getGroupLatestLocations GETs v1_groups_{groupId}_locations_latest and tolerates a null location`() =
        runTest {
            server.enqueue(
                MockResponse().setResponseCode(200).setBody(
                    """
                    {"data":{"members":[
                        {"userId":"u1","displayName":"Eric","role":"owner",
                          "location":{"lat":51.0543,"lon":3.7174,"accuracyM":15.0,
                                       "recordedAt":"2026-07-21T09:58:00Z",
                                       "receivedAt":"2026-07-21T09:58:02Z","isStale":false}},
                        {"userId":"u9","displayName":"Noor","role":"member","location":null}]},
                     $featuresJson}
                    """.trimIndent(),
                ),
            )

            val result = client.getGroupLatestLocations("grp_1")

            assertTrue(result is ApiResult.Success)
            result as ApiResult.Success
            val members = result.data.members
            assertEquals(2, members.size)
            assertEquals(51.0543, members[0].location?.lat)
            assertEquals(false, members[0].location?.isStale)
            assertNull(members[1].location)

            val recorded = server.takeRequest()
            assertEquals("GET", recorded.method)
            assertEquals("/v1/groups/grp_1/locations/latest", recorded.path)
        }

    @Test
    fun `getGroupLatestLocations surfaces GROUP_EXPIRED for a non-active group`() = runTest {
        server.enqueue(
            MockResponse().setResponseCode(410).setBody(
                """{"error":{"code":"GROUP_EXPIRED","message":"ended","requestId":"r_e1"}}""",
            ),
        )

        val result = client.getGroupLatestLocations("grp_1")

        assertTrue(result is ApiResult.Failure)
        assertTrue((result as ApiResult.Failure).error is ApiError.GroupExpired)
    }
}
