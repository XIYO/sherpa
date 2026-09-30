import Foundation
import SherpaMailShim
import SherpaReminderKitShim
import Testing
@testable import SherpaNativeCommandAdapter

@Test func imessageSendValidatesTheExactChatBeforeDispatch() throws {
    let fixture = try FixtureScript(body: """
    if [ "$1" = group ]; then
      printf '%s\n' '{"chat_id":7,"display_name":"Exact"}'
      exit 0
    fi
    if [ "$1" = send ]; then
      printf '%s\n' '{"accepted":true}'
      exit 0
    fi
    exit 2
    """)
    let output = try IMessageAdapter(executable: fixture.url).send(
        chatID: 7, text: Data("hello".utf8)
    )
    #expect(String(decoding: output, as: UTF8.self).contains("accepted"))
}

@Test func imessageSendRejectsAMismatchedChatWithoutDispatching() throws {
    let fixture = try FixtureScript(body: """
    if [ "$1" = group ]; then
      printf '%s\n' '{"chat_id":8,"display_name":"Wrong"}'
      exit 0
    fi
    exit 90
    """)
    #expect(throws: NativeCommandError.failed) {
        _ = try IMessageAdapter(executable: fixture.url).send(
            chatID: 7, text: Data("hello".utf8)
        )
    }
}

@Test func commandRunnerBoundsOutput() throws {
    let fixture = try FixtureScript(body: "head -c 32 /dev/zero")
    #expect(throws: NativeCommandError.outputTooLarge) {
        _ = try NativeCommandRunner().run(executable: fixture.url, arguments: [], outputLimit: 8)
    }
}

@Test func commandRunnerReportsAMutationWhoseOutputOverflowsAsUncertain() throws {
    let fixture = try FixtureScript(body: "head -c 32 /dev/zero")
    #expect(throws: NativeCommandError.uncertain) {
        _ = try NativeCommandRunner().run(
            executable: fixture.url, arguments: [], outputLimit: 8, effect: .mutation
        )
    }
}

@Test func commandRunnerTreatsStdinReadFailureAsFailedRatherThanUncertain() throws {
    let fixture = try FixtureScript(body: "exit 7")
    #expect(throws: NativeCommandError.failed) {
        _ = try NativeCommandRunner().run(
            executable: fixture.url,
            arguments: [],
            stdin: Data("read query".utf8),
            effect: .read
        )
    }
}

@Test func kakaotalkLocalSearchProjectsBoundedRowsWithoutNativeIdentifiers() throws {
    let fixture = try FixtureScript(body: """
    if [ "$1" = search ]; then
      printf '[{"id":99,"chat_id":123,"timestamp":"2030-01-02T03:00:00Z","sender":"%s|%s|%s|%s|%s|%s","text":"설치 완료","type":"text","is_from_me":false}]\n' "$1" "$2" "$3" "$4" "$5" "$6"
      exit 0
    fi
    if [ "$1" = chats ]; then
      printf '%s\n' '[{"id":123,"display_name":"예시 배송센터"}]'
      exit 0
    fi
    exit 90
    """)
    let output = try KakaoTalkLocalSearchAdapter(executable: fixture.url).search(
        query: Data("냉장고".utf8), limit: 20
    )
    let object = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
    #expect(object["schema"] as? String == "sherpa.kakaotalk-local-search.v1")
    #expect(object["source"] as? String == "mac_local_synchronized_database")
    #expect(object["returned_count"] as? Int == 1)
    let coverage = try #require(object["coverage"] as? [String: Any])
    #expect(coverage["completeness"] as? String == "partial")
    let results = try #require(object["results"] as? [[String: Any]])
    #expect(results.first?["reference"] as? String == "KLS001")
    #expect(results.first?["chat"] as? String == "예시 배송센터")
    #expect(results.first?["sender"] as? String == "search|--limit|20|--json|--|냉장고")
    #expect(results.first?["text"] as? String == "설치 완료")
    let rendered = String(decoding: output, as: UTF8.self)
    #expect(!rendered.contains("chat_id"))
    #expect(!rendered.contains("\"id\""))
    #expect(!rendered.contains("123"))
}

@Test func kakaotalkLocalSearchRejectsUnsafeBoundsBeforeLaunching() throws {
    let fixture = try FixtureScript(body: "exit 91")
    let adapter = KakaoTalkLocalSearchAdapter(executable: fixture.url)
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try adapter.search(query: Data(), limit: 20)
    }
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try adapter.search(query: Data("냉장고\n배송".utf8), limit: 20)
    }
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try adapter.search(query: Data("냉장고".utf8), limit: 101)
    }
}

@Test func kakaotalkLocalSearchRejectsMalformedUpstreamJSON() throws {
    let fixture = try FixtureScript(body: "printf '%s\\n' '{}'")
    #expect(throws: NativeCommandError.failed) {
        _ = try KakaoTalkLocalSearchAdapter(executable: fixture.url).search(
            query: Data("냉장고".utf8), limit: 20
        )
    }
}

@Test func kakaotalkLocalHistoryUsesAnExactRoomAndDeclaresTheUnreadPast() throws {
    let fixture = try FixtureScript(body: """
    if [ "$1" = chats ]; then
      printf '%s\n' '[{"id":123,"display_name":"친구방"},{"id":456,"display_name":"친구방 확장"}]'
      exit 0
    fi
    if [ "$1" = messages ]; then
      printf '[{"id":98,"chat_id":123,"timestamp":"2026-08-16T00:59:00Z","sender":null,"text":"native-system-payload-999","type":"system","is_from_me":false},{"id":99,"chat_id":123,"timestamp":"2026-08-16T01:00:00Z","sender":"%s|%s|%s|%s|%s|%s|%s|%s","text":"정산하자","type":"text","is_from_me":false}]\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
      exit 0
    fi
    exit 90
    """)
    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-17T00:00:00Z"))
    let output = try KakaoTalkLocalSearchAdapter(executable: fixture.url).history(
        chatName: Data("친구방".utf8), limit: 1_000, now: now
    )
    let object = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
    #expect(object["schema"] as? String == "sherpa.kakaotalk-local-history.v1")
    #expect(object["source"] as? String == "mac_local_synchronized_database")
    #expect(object["returned_count"] as? Int == 1)
    #expect(object["omitted_unsupported_count"] as? Int == 1)
    let baseline = try #require(object["baseline"] as? [String: Any])
    #expect(baseline["kind"] as? String == "checkpoint_missing_local_seven_day_window")
    #expect(baseline["checkpoint_available"] as? Bool == false)
    #expect(baseline["earlier_history_read"] as? Bool == false)
    #expect(baseline["window_start"] as? String == "2026-08-10T00:00:00.000Z")
    #expect(baseline["window_end"] as? String == "2026-08-17T00:00:00.000Z")
    let results = try #require(object["results"] as? [[String: Any]])
    #expect(results.first?["reference"] as? String == "KLH001")
    #expect(results.first?["chat"] as? String == "친구방")
    #expect(results.first?["sender"] as? String == "messages|--since|7d|--limit|1000|--json|--chat|친구방")
    #expect(results.first?["text"] as? String == "정산하자")
    let rendered = String(decoding: output, as: UTF8.self)
    #expect(!rendered.contains("chat_id"))
    #expect(!rendered.contains("sender_id"))
    #expect(!rendered.contains("\"id\""))
    #expect(!rendered.contains("123"))
    #expect(!rendered.contains("999"))
}

@Test func kakaotalkLocalHistoryRejectsAmbiguousRoomsAndUnsafeBounds() throws {
    let ambiguous = try FixtureScript(body: """
    if [ "$1" = chats ]; then
      printf '%s\n' '[{"id":123,"display_name":"친구방"},{"id":456,"display_name":"친구방"}]'
      exit 0
    fi
    exit 90
    """)
    let adapter = KakaoTalkLocalSearchAdapter(executable: ambiguous.url)
    #expect(throws: NativeCommandError.failed) {
        _ = try adapter.history(chatName: Data("친구방".utf8), limit: 1_000)
    }
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try adapter.history(chatName: Data("친구방\n다른방".utf8), limit: 1_000)
    }
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try adapter.history(chatName: Data("친구방".utf8), limit: 1_001)
    }
}

@Test func kakaotalkLocalArchiveReadsAllRoomsFromAnExactLocalDate() throws {
    let fixture = try FixtureScript(body: """
    if [ "$1" = messages ]; then
      printf '[{"id":1,"chat_id":123,"timestamp":"2026-06-30T14:59:59Z","sender":"old","text":"before","type":"text","is_from_me":false},{"id":2,"chat_id":123,"timestamp":"2026-06-30T15:00:00Z","sender":"friend","text":"병원 예약","type":"text","is_from_me":false},{"id":3,"chat_id":456,"timestamp":"2026-07-02T01:00:00Z","sender":null,"text":"native-system-999","type":"system","is_from_me":false},{"id":4,"chat_id":456,"timestamp":"2026-07-03T01:00:00Z","sender":"me","text":"보험 서류 보내기","type":"text","is_from_me":true},{"id":5,"chat_id":456,"timestamp":"2026-07-03T02:00:00Z","sender":null,"type":"unknown","is_from_me":false}]\n'
      exit 0
    fi
    if [ "$1" = chats ]; then
      printf '%s\n' '[{"id":123,"display_name":"가족방"},{"id":456,"display_name":"친구방"}]'
      exit 0
    fi
    exit 90
    """)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sherpa-kakao-checkpoint-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try KakaoTalkLocalCheckpointStore(url: directory.appendingPathComponent("state.sqlite3"))
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-04T00:00:00Z"))
    let output = try KakaoTalkLocalSearchAdapter(
        executable: fixture.url, checkpointStore: store
    ).archive(since: "2026-07-01", timeZoneIdentifier: "Asia/Seoul", limit: 50_000, now: now)

    let object = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
    #expect(object["schema"] as? String == "sherpa.kakaotalk-local-archive.v1")
    #expect(object["returned_count"] as? Int == 2)
    #expect(object["returned_chat_count"] as? Int == 2)
    #expect(object["omitted_unsupported_count"] as? Int == 2)
    let range = try #require(object["range"] as? [String: Any])
    #expect(range["requested_start"] as? String == "2026-07-01")
    #expect(range["window_start"] as? String == "2026-06-30T15:00:00.000Z")
    #expect(range["earlier_history_read"] as? Bool == false)
    let coverage = try #require(object["coverage"] as? [String: Any])
    #expect(coverage["limit_reached"] as? Bool == false)
    let checkpoint = try #require(object["checkpoint"] as? [String: Any])
    #expect(checkpoint["state"] as? String == "pending")
    #expect((checkpoint["token"] as? String)?.hasPrefix("KLCP") == true)
    let results = try #require(object["results"] as? [[String: Any]])
    #expect(results.map { $0["reference"] as? String } == ["KLA00001", "KLA00002"])
    #expect(results.map { $0["chat"] as? String } == ["가족방", "친구방"])
    #expect(results.map { $0["text"] as? String } == ["병원 예약", "보험 서류 보내기"])
    let rendered = String(decoding: output, as: UTF8.self)
    #expect(!rendered.contains("chat_id"))
    #expect(!rendered.contains("native-system"))
    #expect(!rendered.contains("\"id\""))
    #expect(!rendered.contains("999"))
}

@Test func kakaotalkLocalArchiveStagesNoCheckpointWhenTheLimitIsReached() throws {
    let fixture = try FixtureScript(body: """
    if [ "$1" = messages ]; then
      printf '%s\n' '[{"id":1,"chat_id":123,"timestamp":"2026-07-01T00:00:00Z","sender":"friend","text":"one","type":"text","is_from_me":false}]'
      exit 0
    fi
    if [ "$1" = chats ]; then
      printf '%s\n' '[{"id":123,"display_name":"친구방"}]'
      exit 0
    fi
    exit 90
    """)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sherpa-kakao-checkpoint-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try KakaoTalkLocalCheckpointStore(url: directory.appendingPathComponent("state.sqlite3"))
    let now = try #require(ISO8601DateFormatter().date(from: "2026-07-02T00:00:00Z"))
    let output = try KakaoTalkLocalSearchAdapter(
        executable: fixture.url, checkpointStore: store
    ).archive(since: "2026-07-01", timeZoneIdentifier: "UTC", limit: 1, now: now)
    let object = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
    #expect(object["checkpoint"] == nil)
    let coverage = try #require(object["coverage"] as? [String: Any])
    #expect(coverage["limit_reached"] as? Bool == true)
    #expect(try store.current() == nil)
}

@Test func kakaotalkLocalCheckpointCommitsOnlyAStagedRead() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sherpa-kakao-checkpoint-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try KakaoTalkLocalCheckpointStore(url: directory.appendingPathComponent("state.sqlite3"))
    let highWater = try #require(ISO8601DateFormatter().date(from: "2026-08-17T10:00:00Z"))
    let pending = try store.stage(highWater: highWater)
    let token = try #require(pending.token)
    let committed = try store.commit(token: token)
    #expect(committed.state == "committed")
    #expect(committed.token == nil)
    #expect(try store.current()?.highWater == "2026-08-17T10:00:00.000Z")
    #expect(throws: NativeCommandError.failed) {
        _ = try store.commit(token: token)
    }
}

@Test func kakaotalkLocalArchiveCanResumeFromTheCommittedCheckpoint() throws {
    let fixture = try FixtureScript(body: """
    if [ "$1" = messages ]; then
      printf '[{"id":1,"chat_id":123,"timestamp":"2026-08-16T01:00:00Z","sender":"%s|%s|%s|%s|%s|%s","text":"new","type":"text","is_from_me":false}]\n' "$1" "$2" "$3" "$4" "$5" "$6"
      exit 0
    fi
    if [ "$1" = chats ]; then
      printf '%s\n' '[{"id":123,"display_name":"친구방"}]'
      exit 0
    fi
    exit 90
    """)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sherpa-kakao-checkpoint-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try KakaoTalkLocalCheckpointStore(url: directory.appendingPathComponent("state.sqlite3"))
    let highWater = try #require(ISO8601DateFormatter().date(from: "2026-08-16T00:00:00Z"))
    let pending = try store.stage(highWater: highWater)
    _ = try store.commit(token: #require(pending.token))
    let now = try #require(ISO8601DateFormatter().date(from: "2026-08-17T00:00:00Z"))
    let output = try KakaoTalkLocalSearchAdapter(
        executable: fixture.url, checkpointStore: store
    ).archive(since: "checkpoint", timeZoneIdentifier: "Asia/Seoul", limit: 50_000, now: now)
    let object = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
    let range = try #require(object["range"] as? [String: Any])
    #expect(range["kind"] as? String == "local_checkpoint_with_overlap")
    #expect(range["checkpoint_available"] as? Bool == true)
    let results = try #require(object["results"] as? [[String: Any]])
    #expect(results.first?["sender"] as? String == "messages|--since|3d|--limit|50000|--json")
}

@Test func kakaotalkLocalArchiveRejectsInvalidRangeInputs() throws {
    let fixture = try FixtureScript(body: "exit 91")
    let adapter = KakaoTalkLocalSearchAdapter(executable: fixture.url)
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try adapter.archive(
            since: "2026-02-30", timeZoneIdentifier: "Asia/Seoul", limit: 50_000
        )
    }
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try adapter.archive(
            since: "2026-07-01", timeZoneIdentifier: "not-a-zone", limit: 50_000
        )
    }
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try adapter.archive(
            since: "2026-07-01", timeZoneIdentifier: "Asia/Seoul", limit: 50_001
        )
    }
}

@Test func mailSendPassesOnlyValidatedPayloadOnStdin() throws {
    let fixture = try FixtureScript(body: "cat >/dev/null; printf '%s\\n' '{\"accepted\":true}'")
    let message = try MailMessage(
        sender: "sender@example.com", to: ["to@example.com"], subject: "subject", body: "body"
    )
    let output = try MailAdapter(osascript: fixture.url).send(message)
    #expect(String(decoding: output, as: UTF8.self).contains("accepted"))
}

@Test func mailMessageRejectsHeaderInjectionAndInvalidRecipients() {
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try MailMessage(to: ["bad address"], subject: "subject\nBcc: x@y.z", body: "body")
    }
}

@Test func mailReaderBuildsBoundedListAndReadRequests() throws {
    let reader = MailReader { request in
        let text = String(decoding: request, as: UTF8.self)
        #expect(text.contains("\"effect\":\"read\""))
        #expect(text.contains("\"required_evidence\":\"none\""))
        #expect(text.contains("\"artifact_directory\":null"))
        if text.contains("mail.messages.list") {
            return Data(#"{"status":"succeeded","result":{"messages":[]},"error":null}"#.utf8)
        }
        return Data(#"{"status":"succeeded","result":{"message":null},"error":null}"#.utf8)
    }
    let list = try reader.list(
        from: "2026-08-01T00:00:00+09:00", to: "2026-08-02T00:00:00+09:00",
        limit: 20, maximumBodyBytes: 16_384
    )
    #expect(list.messages.isEmpty)
    #expect(try reader.read(sourceMessageID: "message@example.test", maximumBodyBytes: 1_024).message == nil)
}

@Test func mailReaderRejectsInvalidRangesBeforeCallingMail() {
    let reader = MailReader { _ in
        Issue.record("Mail handler must not run for invalid input")
        return Data()
    }
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try reader.list(from: "invalid", to: "2026-08-02T00:00:00Z", limit: 20, maximumBodyBytes: 1_024)
    }
    #expect(throws: NativeCommandError.invalidRequest) {
        _ = try reader.read(sourceMessageID: "", maximumBodyBytes: 1_024)
    }
}

@Test func mutationStoreAllowsOneTerminalTransitionWithoutContent() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sherpa-native-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try NativeMutationStore(url: directory.appendingPathComponent("state.sqlite3"))
    let operation = try store.start(capability: "imessage.send")
    try store.finish(operationID: operation, status: .uncertain, stableErrorCode: "uncertain")
    #expect(throws: NativeCommandError.failed) {
        try store.finish(operationID: operation, status: .completed)
    }
    let record = try #require(store.recent(limit: 1).first)
    #expect(record.operationID == operation)
    #expect(record.status == .uncertain)
    #expect(record.capability == "imessage.send")
}

@Test func inProcessMailShimAnswersCapabilitiesWithoutLaunchingAWorker() throws {
    let request = Data(#"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.mail.v2","request_id":"req-test","operation_id":"op-test","capability":"capabilities","payload":{},"deadline_ms":1000,"idempotency_key":"idem-test","policy":{"effect":"read","required_evidence":"none","artifact_directory":null}}"#.utf8)
    let response = SherpaMailHandleRequest(request)
    let text = String(decoding: response, as: UTF8.self)
    #expect(text.contains("mail.messages.list"))
    #expect(text.contains("\"status\":\"succeeded\""))
}

@Test func inProcessReminderKitShimAnswersCapabilitiesWithoutLaunchingAWorker() {
    let request = Data(#"{"kind":"request","protocol_version":"2.0.0","application_contract":"sherpa.reminder-private.v2","request_id":"req-test","operation_id":"op-test","capability":"capabilities","payload":{},"deadline_ms":1000,"idempotency_key":"idem-test","policy":{"effect":"read","required_evidence":"none","artifact_directory":null}}"#.utf8)
    let response = SherpaReminderKitHandleRequest(request)
    let text = String(decoding: response, as: UTF8.self)
    #expect(text.contains("sherpa.worker-capabilities.v2"))
    #expect(text.contains("\"status\":\"succeeded\""))
}

final class FixtureScript {
    let directory: URL
    let url: URL

    init(body: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sherpa-native-test-\(UUID().uuidString)", isDirectory: true)
        url = directory.appendingPathComponent("fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: url.path
        )
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
