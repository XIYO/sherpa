import Foundation

public struct MailMessage: Codable, Sendable, Equatable {
    public let sender: String?
    public let to: [String]
    public let cc: [String]
    public let bcc: [String]
    public let subject: String
    public let body: String

    public init(
        sender: String? = nil,
        to: [String],
        cc: [String] = [],
        bcc: [String] = [],
        subject: String,
        body: String
    ) throws {
        guard !to.isEmpty, to.count + cc.count + bcc.count <= 100,
              [subject, body].allSatisfy({ !$0.contains("\0") }),
              !subject.contains("\r"), !subject.contains("\n"),
              subject.utf8.count <= 8 * 1_024, body.utf8.count <= 1_024 * 1_024,
              (to + cc + bcc).allSatisfy(validMailbox), sender.map(validMailbox) ?? true
        else { throw NativeCommandError.invalidRequest }
        self.sender = sender
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sender: try values.decodeIfPresent(String.self, forKey: .sender),
            to: try values.decode([String].self, forKey: .to),
            cc: try values.decode([String].self, forKey: .cc),
            bcc: try values.decode([String].self, forKey: .bcc),
            subject: try values.decode(String.self, forKey: .subject),
            body: try values.decode(String.self, forKey: .body)
        )
    }
}

public struct MailAdapter: Sendable {
    private let osascript: URL
    private let runner: NativeCommandRunner

    public init(osascript: URL, runner: NativeCommandRunner = .init()) {
        self.osascript = osascript
        self.runner = runner
    }

    public func authorizationStatus() throws -> Data {
        try runner.run(
            executable: osascript,
            arguments: ["-l", "JavaScript", "-e", Self.authorizationScript]
        ).stdout
    }

    public func send(_ message: MailMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        return try runner.run(
            executable: osascript,
            arguments: ["-l", "JavaScript", "-e", Self.sendScript],
            stdin: payload,
            timeoutSeconds: 120,
            outputLimit: 1_024 * 1_024,
            effect: .mutation
        ).stdout
    }

    private static let authorizationScript = #"""
    ObjC.import('Foundation');
    const Mail = Application('Mail');
    Mail.name();
    JSON.stringify({authorized:true});
    """#

    private static let sendScript = #"""
    ObjC.import('Foundation');
    function input() {
      const data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
      const value = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
      if (!value) throw new Error('invalid utf8');
      return JSON.parse(ObjC.unwrap(value));
    }
    function recipient(Mail, kind, address) {
      if (kind === 'to') return Mail.ToRecipient({address: address});
      if (kind === 'cc') return Mail.CcRecipient({address: address});
      return Mail.BccRecipient({address: address});
    }
    const payload = input();
    const Mail = Application('Mail');
    const message = Mail.OutgoingMessage({
      subject: payload.subject,
      content: payload.body,
      visible: false
    });
    Mail.outgoingMessages.push(message);
    payload.to.forEach(x => message.toRecipients.push(recipient(Mail, 'to', x)));
    payload.cc.forEach(x => message.ccRecipients.push(recipient(Mail, 'cc', x)));
    payload.bcc.forEach(x => message.bccRecipients.push(recipient(Mail, 'bcc', x)));
    if (payload.sender) message.sender = payload.sender;
    message.send();
    JSON.stringify({accepted:true});
    """#
}

private func validMailbox(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.count <= 320, !value.contains(where: { $0.isWhitespace })
    else { return false }
    let parts = value.split(separator: "@", omittingEmptySubsequences: false)
    return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
}
