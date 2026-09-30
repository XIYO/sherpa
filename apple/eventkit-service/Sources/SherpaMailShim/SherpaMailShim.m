#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>
#import "SherpaMailShim.h"

#include <stdio.h>
#include <stdlib.h>

static NSString *const ProtocolVersion = @"2.0.0";
static NSString *const ApplicationContract = @"sherpa.mail.v2";
static NSString *CurrentOperationID = @"unknown";
static NSString *CurrentCapability = @"unknown";
static NSString *const MailBundleIdentifier = @"com.apple.mail";
static const NSUInteger MaxRequestBytes = 2 * 1024 * 1024;
static const NSUInteger MaxResponseBytes = 32 * 1024 * 1024;
static const NSInteger MaxMessages = 50000;
static const NSInteger MaxBodyBytes = 1024 * 1024;

static const AEEventClass AppleScriptSuite = 0x61736372; // ascr
static const AEEventID AppleScriptSubroutine = 0x70736272; // psbr
static const AEKeyword AppleScriptSubroutineName = 0x736e616d; // snam

static NSString *const MailCollectionScript =
@"on optionalText(valueToRead)\n"
 "  if valueToRead is missing value then return \"\"\n"
 "  return valueToRead as text\n"
 "end optionalText\n"
 "\n"
 "on recipientRows(recipientValues, roleName)\n"
 "  set outputRows to {}\n"
 "  repeat with recipientValue in recipientValues\n"
 "    set displayName to \"\"\n"
 "    set addressText to \"\"\n"
 "    try\n"
 "      tell application \"Mail\" to set displayName to my optionalText(name of recipientValue)\n"
 "    end try\n"
 "    try\n"
 "      tell application \"Mail\" to set addressText to my optionalText(address of recipientValue)\n"
 "    end try\n"
 "    set end of outputRows to {roleName, displayName, addressText}\n"
 "  end repeat\n"
 "  return outputRows\n"
 "end recipientRows\n"
 "\n"
 "on attachmentRows(attachmentValues)\n"
 "  set outputRows to {}\n"
 "  repeat with attachmentValue in attachmentValues\n"
 "    set mimeText to \"\"\n"
 "    set byteCount to 0\n"
 "    set isDownloaded to false\n"
 "    try\n"
 "      tell application \"Mail\"\n"
 "        set mimeText to my optionalText(MIME type of attachmentValue)\n"
 "        set byteCount to file size of attachmentValue\n"
 "        set isDownloaded to downloaded of attachmentValue\n"
 "      end tell\n"
 "    end try\n"
 "    set end of outputRows to {mimeText, byteCount, isDownloaded}\n"
 "  end repeat\n"
 "  return outputRows\n"
 "end attachmentRows\n"
 "\n"
 "on messageRow(currentMessage, bodyCharacterLimit)\n"
 "  tell application \"Mail\"\n"
 "    set sourceIdentifier to my optionalText(message id of currentMessage)\n"
 "    if sourceIdentifier is \"\" then set sourceIdentifier to \"local:\" & (id of currentMessage as text)\n"
 "    set subjectText to my optionalText(subject of currentMessage)\n"
 "    set senderText to my optionalText(sender of currentMessage)\n"
 "    set bodyText to \"\"\n"
 "    set bodyWasTruncated to false\n"
 "    if bodyCharacterLimit > 0 then\n"
 "      set bodyText to my optionalText(content of currentMessage)\n"
 "      if (count characters of bodyText) > bodyCharacterLimit then\n"
 "        set bodyText to text 1 thru bodyCharacterLimit of bodyText\n"
 "        set bodyWasTruncated to true\n"
 "      end if\n"
 "    end if\n"
 "    set mailboxText to \"\"\n"
 "    try\n"
 "      set mailboxText to my optionalText(name of mailbox of currentMessage)\n"
 "    end try\n"
 "    set toRows to my recipientRows(to recipients of currentMessage, \"to\")\n"
 "    set ccRows to my recipientRows(cc recipients of currentMessage, \"cc\")\n"
 "    set bccRows to my recipientRows(bcc recipients of currentMessage, \"bcc\")\n"
 "    set fileRows to my attachmentRows(mail attachments of currentMessage)\n"
 "    return {sourceIdentifier, subjectText, senderText, date received of currentMessage, date sent of currentMessage, bodyText, bodyWasTruncated, mailboxText, toRows, ccRows, bccRows, fileRows}\n"
 "  end tell\n"
 "end messageRow\n"
 "\n"
 "on collectMessages(startDate, endDate, messageLimit, bodyCharacterLimit)\n"
 "  with timeout of 15 seconds\n"
 "  tell application \"Mail\"\n"
 "    set outputRows to {}\n"
 "    repeat with messageIndex from 1 to messageLimit\n"
 "      try\n"
 "        set currentMessage to message messageIndex of inbox\n"
 "      on error\n"
 "        exit repeat\n"
 "      end try\n"
 "      set receivedAt to date received of currentMessage\n"
 "      if receivedAt is greater than or equal to startDate and receivedAt is less than endDate then\n"
 "        set end of outputRows to my messageRow(currentMessage, bodyCharacterLimit)\n"
 "      end if\n"
 "    end repeat\n"
 "    return outputRows\n"
 "  end tell\n"
 "  end timeout\n"
 "end collectMessages\n"
 "\n"
 "on collectMessageByIdentifier(sourceIdentifier, bodyCharacterLimit)\n"
 "  with timeout of 15 seconds\n"
 "  tell application \"Mail\"\n"
 "    if sourceIdentifier starts with \"local:\" then\n"
 "      try\n"
 "        set localIdentifier to (text 7 thru -1 of sourceIdentifier) as integer\n"
 "      on error\n"
 "        return {}\n"
 "      end try\n"
 "      set candidates to every message of inbox whose id is localIdentifier\n"
 "    else\n"
 "      set candidates to every message of inbox whose message id is sourceIdentifier\n"
 "    end if\n"
 "    if (count of candidates) is 0 then return {}\n"
 "    if (count of candidates) is not 1 then error \"ambiguous message identifier\"\n"
 "    return {my messageRow(item 1 of candidates, bodyCharacterLimit)}\n"
 "  end tell\n"
 "  end timeout\n"
 "end collectMessageByIdentifier\n"
 "\n"
 "on sendMessage(accountSelector, senderAddress, toValues, ccValues, bccValues, subjectText, bodyText)\n"
 "  set matchingAccounts to {}\n"
 "  tell application \"Mail\"\n"
 "    repeat with accountValue in every account\n"
 "      try\n"
 "        if enabled of accountValue then\n"
 "          set configuredAddresses to email addresses of accountValue\n"
 "          if senderAddress is in configuredAddresses then set end of matchingAccounts to accountValue\n"
 "        end if\n"
 "      end try\n"
 "    end repeat\n"
 "    if (count of matchingAccounts) is 0 then return \"sender_not_found\"\n"
 "    if (count of matchingAccounts) is not 1 then return \"sender_ambiguous\"\n"
 "    set selectedAccount to item 1 of matchingAccounts\n"
 "    if accountSelector is not \"\" then\n"
 "      set selectedName to my optionalText(name of selectedAccount)\n"
 "      set selectedIdentifier to my optionalText(id of selectedAccount)\n"
 "      if accountSelector is not selectedName and accountSelector is not selectedIdentifier then return \"account_mismatch\"\n"
 "    end if\n"
 "    set outgoingMessage to make new outgoing message with properties {sender:senderAddress, subject:subjectText, content:bodyText, visible:false}\n"
 "    tell outgoingMessage\n"
 "      repeat with addressValue in toValues\n"
 "        make new to recipient at end of to recipients with properties {address:(addressValue as text)}\n"
 "      end repeat\n"
 "      repeat with addressValue in ccValues\n"
 "        make new cc recipient at end of cc recipients with properties {address:(addressValue as text)}\n"
 "      end repeat\n"
 "      repeat with addressValue in bccValues\n"
 "        make new bcc recipient at end of bcc recipients with properties {address:(addressValue as text)}\n"
 "      end repeat\n"
 "    end tell\n"
 "    if send outgoingMessage then return \"application_accepted\"\n"
 "    return \"send_rejected\"\n"
 "  end tell\n"
 "end sendMessage\n";

static BOOL LogInfoEnabled(void) {
    NSString *level = [[[NSProcessInfo processInfo] environment][@"LOG_LEVEL"] lowercaseString];
    return [level isEqualToString:@"info"] || [level isEqualToString:@"debug"] ||
           [level isEqualToString:@"trace"];
}

static void LogInfo(NSString *message) {
    if (LogInfoEnabled()) {
        fprintf(stderr, "%s\n", message.UTF8String);
    }
}

static void LogFailure(NSString *code) {
    fprintf(stderr, "[worker:mail:request:failure] code=%s\n", code.UTF8String);
}

static BOOL SafeIdentifier(id value) {
    if (![value isKindOfClass:[NSString class]]) return NO;
    NSData *bytes = [(NSString *)value dataUsingEncoding:NSUTF8StringEncoding];
    if (bytes.length == 0 || bytes.length > 128) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"];
    return [[(NSString *)value stringByTrimmingCharactersInSet:allowed] length] == 0;
}

static BOOL ExactKeys(NSDictionary *object, NSArray<NSString *> *keys) {
    return [NSSet setWithArray:object.allKeys].count == keys.count &&
           [[NSSet setWithArray:object.allKeys] isEqualToSet:[NSSet setWithArray:keys]];
}

static BOOL ContainsNul(NSString *value) {
    for (NSUInteger index = 0; index < value.length; index += 1) {
        if ([value characterAtIndex:index] == 0) return YES;
    }
    return NO;
}

static BOOL ValidBoundedString(id value, NSUInteger maximumBytes, BOOL allowEmpty) {
    if (![value isKindOfClass:[NSString class]] || ContainsNul(value)) return NO;
    NSUInteger byteCount = [(NSString *)value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    return byteCount <= maximumBytes && (allowEmpty || byteCount > 0);
}

static BOOL ValidHeader(id value, NSUInteger maximumBytes, BOOL allowEmpty) {
    if (!ValidBoundedString(value, maximumBytes, allowEmpty)) return NO;
    NSString *text = (NSString *)value;
    return [text rangeOfString:@"\r"].location == NSNotFound &&
           [text rangeOfString:@"\n"].location == NSNotFound;
}

static BOOL ValidMailbox(id value) {
    if (!ValidHeader(value, 4096, NO)) return NO;
    NSString *mailbox = (NSString *)value;
    if ([mailbox rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location !=
        NSNotFound) return NO;
    NSRange separator = [mailbox rangeOfString:@"@" options:NSBackwardsSearch];
    if (separator.location == NSNotFound || separator.location == 0 ||
        NSMaxRange(separator) >= mailbox.length) return NO;
    NSString *domain = [mailbox substringFromIndex:NSMaxRange(separator)];
    return ![domain hasPrefix:@"."] && ![domain hasSuffix:@"."];
}

static BOOL ValidMailboxArray(id value) {
    if (![value isKindOfClass:[NSArray class]]) return NO;
    for (id mailbox in (NSArray *)value) {
        if (!ValidMailbox(mailbox)) return NO;
    }
    return YES;
}

static BOOL ValidPolicyShape(NSDictionary *policy) {
    NSSet *allowedKeys = [NSSet setWithArray:
        @[@"effect", @"required_evidence", @"artifact_directory"]];
    if (![[NSSet setWithArray:policy.allKeys] isEqualToSet:allowedKeys] ||
        ![policy[@"effect"] isKindOfClass:[NSString class]]) return NO;
    if (![policy[@"required_evidence"] isKindOfClass:[NSString class]]) return NO;
    id artifact = policy[@"artifact_directory"];
    if (!artifact || artifact == [NSNull null]) return YES;
    if (![artifact isKindOfClass:[NSString class]]) return NO;
    NSData *bytes = [artifact dataUsingEncoding:NSUTF8StringEncoding];
    return bytes.length > 0 && bytes.length <= 4096 && !ContainsNul(artifact);
}

static BOOL PolicyMatches(NSDictionary *policy, NSString *effect,
                          NSString *requiredEvidence) {
    id artifact = policy[@"artifact_directory"];
    return [policy[@"effect"] isEqual:effect] &&
           [policy[@"required_evidence"] isEqual:requiredEvidence] &&
           (!artifact || artifact == [NSNull null]);
}

static NSDictionary *Response(NSString *requestID, NSString *status, NSDictionary *result,
                              NSString *code, NSString *retry) {
    return @{
        @"kind": @"response",
        @"protocol_version": ProtocolVersion,
        @"application_contract": ApplicationContract,
        @"request_id": requestID ?: @"unknown",
        @"operation_id": CurrentOperationID,
        @"capability": CurrentCapability,
        @"status": status,
        @"result": result ?: [NSNull null],
        @"effect": @{ @"kind": @"none", @"state": code ? @"not_started" : @"not_applicable" },
        @"evidence": [NSNull null],
        @"error": code ? @{ @"code": code, @"retry": retry } : [NSNull null],
        @"warnings": @[],
    };
}

static NSDictionary *Success(NSString *requestID, NSDictionary *result) {
    NSMutableDictionary *response = [Response(requestID, @"succeeded", result, nil, @"never") mutableCopy];
    if ([CurrentCapability isEqual:@"mail.message.send"]) {
        response[@"effect"] = @{ @"kind": @"outbound_dispatch", @"state": @"applied" };
        response[@"evidence"] = @{ @"kind": @"application_acceptance", @"state": @"matched" };
    } else if ([CurrentCapability isEqual:@"mail.authorization.request"]) {
        response[@"effect"] = @{ @"kind": @"authorization_prompt", @"state": @"applied" };
        response[@"evidence"] = @{ @"kind": @"authorization_readback", @"state": @"matched" };
    }
    return response;
}

static NSDictionary *MailDescriptor(NSString *name, NSString *effect, NSString *evidence) {
    return @{ @"capability": name, @"application_contract": ApplicationContract,
        @"request_schema": [NSString stringWithFormat:@"sherpa.%@.request.v2", name],
        @"success_schema": [NSString stringWithFormat:@"sherpa.%@.success.v2", name],
        @"partial_schema": [NSNull null], @"uncertain_schema": [NSNull null],
        @"effect": effect, @"required_evidence": evidence, @"artifact_policy": @"none",
        @"destination": @"none", @"state": @"supported", @"stable_reason_code": [NSNull null] };
}

static NSDictionary *Failure(NSString *requestID, NSString *code, NSString *retry,
                              NSString *capabilityState) {
    (void)capabilityState;
    return Response(requestID, @"failed", nil, code, retry);
}

static NSString *AuthorizationState(BOOL askUser) {
    NSArray<NSRunningApplication *> *applications =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:MailBundleIdentifier];
    if (applications.count == 0) return @"target_not_running";
    NSData *bundleBytes = [MailBundleIdentifier dataUsingEncoding:NSUTF8StringEncoding];
    AEAddressDesc target = {typeNull, NULL};
    OSStatus createStatus = AECreateDesc(typeApplicationBundleID, bundleBytes.bytes,
                                         bundleBytes.length, &target);
    if (createStatus != noErr) return @"unknown";
    OSStatus status = AEDeterminePermissionToAutomateTarget(
        &target, typeWildCard, typeWildCard, askUser ? true : false);
    AEDisposeDesc(&target);
    if (status == noErr) return @"authorized";
    if (status == errAEEventWouldRequireUserConsent) return @"consent_required";
    if (status == errAEEventNotPermitted) return @"denied";
    if (status == procNotFound) return @"target_not_running";
    return @"unknown";
}

static NSDate *ParseDate(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                              NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [formatter dateFromString:value];
    if (date) return date;
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [formatter dateFromString:value];
}

static NSString *FormatDate(NSDate *date) {
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    return [formatter stringFromDate:date];
}

static NSString *DescriptorString(NSAppleEventDescriptor *descriptor) {
    NSString *value = descriptor.stringValue;
    return value ?: @"";
}

static NSString *TruncateUTF8(NSString *value, NSUInteger maxBytes, BOOL *wasTruncated) {
    NSData *encoded = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!encoded) {
        *wasTruncated = YES;
        return @"";
    }
    if (encoded.length <= maxBytes) return value;

    // UTF-8 scalars use at most four bytes. Starting at the exact byte bound
    // and backing up until decoding succeeds preserves the largest valid
    // prefix without exposing a partial scalar in the protocol response.
    NSUInteger prefixLength = maxBytes;
    while (prefixLength > 0) {
        NSData *prefix = [encoded subdataWithRange:NSMakeRange(0, prefixLength)];
        NSString *decoded = [[NSString alloc] initWithData:prefix
                                                   encoding:NSUTF8StringEncoding];
        if (decoded) {
            *wasTruncated = YES;
            return decoded;
        }
        prefixLength -= 1;
    }
    *wasTruncated = YES;
    return @"";
}

static NSArray *DecodeRecipients(NSAppleEventDescriptor *descriptor, NSString **errorCode) {
    NSMutableArray *values = [NSMutableArray array];
    for (NSInteger index = 1; index <= descriptor.numberOfItems; index += 1) {
        NSAppleEventDescriptor *row = [descriptor descriptorAtIndex:index];
        if (row.numberOfItems != 3) {
            *errorCode = @"mail.incompatible_result";
            return nil;
        }
        NSString *role = DescriptorString([row descriptorAtIndex:1]);
        NSString *name = DescriptorString([row descriptorAtIndex:2]);
        NSString *address = DescriptorString([row descriptorAtIndex:3]);
        if (![@[@"to", @"cc", @"bcc"] containsObject:role] || address.length > 4096 ||
            name.length > 4096) {
            *errorCode = @"mail.incompatible_result";
            return nil;
        }
        [values addObject:@{
            @"role": role,
            @"name": name.length > 0 ? name : [NSNull null],
            @"address": address,
        }];
    }
    return values;
}

static NSArray *DecodeAttachments(NSAppleEventDescriptor *descriptor, NSString **errorCode) {
    NSMutableArray *values = [NSMutableArray array];
    for (NSInteger index = 1; index <= descriptor.numberOfItems; index += 1) {
        NSAppleEventDescriptor *row = [descriptor descriptorAtIndex:index];
        if (row.numberOfItems != 3) {
            *errorCode = @"mail.incompatible_result";
            return nil;
        }
        NSString *mime = DescriptorString([row descriptorAtIndex:1]);
        NSInteger byteCount = [row descriptorAtIndex:2].int32Value;
        BOOL downloaded = [row descriptorAtIndex:3].booleanValue;
        if (mime.length > 512 || byteCount < 0) {
            *errorCode = @"mail.incompatible_result";
            return nil;
        }
        [values addObject:@{
            @"mime_type": mime.length > 0 ? mime : [NSNull null],
            @"byte_count": @(byteCount),
            @"downloaded": @(downloaded),
        }];
    }
    return values;
}

static NSAppleScript *CompiledMailScript(NSString **errorCode) {
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:MailCollectionScript];
    NSDictionary *compileError = nil;
    if (![script compileAndReturnError:&compileError]) {
#if defined(SHERPA_MAIL_SCRIPT_DIAGNOSTIC)
        NSValue *rangeValue = compileError[NSAppleScriptErrorRange];
        if ([rangeValue isKindOfClass:[NSValue class]]) {
            NSRange range = rangeValue.rangeValue;
            fprintf(stderr,
                    "[worker:mail:script:failure] code=compile_error range_location=%lu "
                    "range_length=%lu\n",
                    (unsigned long)range.location, (unsigned long)range.length);
        } else {
            fprintf(stderr, "[worker:mail:script:failure] code=compile_error\n");
        }
#endif
        *errorCode = @"mail.script_incompatible";
        return nil;
    }
    return script;
}

static NSArray *DecodeCollectedMessages(NSAppleEventDescriptor *result,
                                         NSInteger maxBodyBytes, NSString **errorCode) {
    NSMutableArray *messages = [NSMutableArray array];
    for (NSInteger index = 1; index <= result.numberOfItems; index += 1) {
        NSAppleEventDescriptor *row = [result descriptorAtIndex:index];
        if (row.numberOfItems != 12) {
            *errorCode = @"mail.incompatible_result";
            return nil;
        }
        NSString *sourceID = DescriptorString([row descriptorAtIndex:1]);
        NSString *subject = DescriptorString([row descriptorAtIndex:2]);
        NSString *sender = DescriptorString([row descriptorAtIndex:3]);
        NSDate *received = [row descriptorAtIndex:4].dateValue;
        NSDate *sent = [row descriptorAtIndex:5].dateValue;
        NSString *body = DescriptorString([row descriptorAtIndex:6]);
        BOOL truncated = [row descriptorAtIndex:7].booleanValue;
        BOOL byteTruncated = NO;
        body = TruncateUTF8(body, (NSUInteger)maxBodyBytes, &byteTruncated);
        truncated = truncated || byteTruncated;
        NSString *mailbox = DescriptorString([row descriptorAtIndex:8]);
        if (sourceID.length == 0 || sourceID.length > 4096 || subject.length > 65536 ||
            sender.length == 0 || sender.length > 4096 || mailbox.length > 4096 ||
            !received || [body lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >
                             (NSUInteger)maxBodyBytes) {
            *errorCode = @"mail.incompatible_result";
            return nil;
        }
        NSMutableArray *recipients = [NSMutableArray array];
        for (NSInteger recipientIndex = 9; recipientIndex <= 11; recipientIndex += 1) {
            NSArray *decoded = DecodeRecipients([row descriptorAtIndex:recipientIndex], errorCode);
            if (!decoded) return nil;
            [recipients addObjectsFromArray:decoded];
        }
        NSArray *attachments = DecodeAttachments([row descriptorAtIndex:12], errorCode);
        if (!attachments) return nil;
        [messages addObject:@{
            @"source_message_id": sourceID,
            @"subject": subject,
            @"sender": sender,
            @"received_at": FormatDate(received),
            @"sent_at": sent ? FormatDate(sent) : [NSNull null],
            @"body": body,
            @"body_truncated": @(truncated),
            @"mailbox": mailbox,
            @"recipients": recipients,
            @"attachments": attachments,
        }];
    }
    return messages;
}

static NSAppleEventDescriptor *ExecuteCollectionHandler(NSString *handler,
                                                         NSAppleEventDescriptor *arguments,
                                                         NSString **errorCode) {
    NSAppleScript *script = CompiledMailScript(errorCode);
    if (!script) return nil;
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor
        appleEventWithEventClass:AppleScriptSuite
                         eventID:AppleScriptSubroutine
                targetDescriptor:[NSAppleEventDescriptor currentProcessDescriptor]
                       returnID:kAutoGenerateReturnID
                  transactionID:kAnyTransactionID];
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:handler]
                   forKeyword:AppleScriptSubroutineName];
    [event setParamDescriptor:arguments forKeyword:keyDirectObject];
    NSDictionary *executionError = nil;
    NSAppleEventDescriptor *result = [script executeAppleEvent:event error:&executionError];
    if (!result) {
        NSNumber *number = executionError[NSAppleScriptErrorNumber];
        if (number.integerValue == errAEEventNotPermitted ||
            number.integerValue == errAEEventWouldRequireUserConsent) {
            *errorCode = @"mail.authorization_required";
        } else {
            *errorCode = @"mail.read_failed";
        }
    }
    return result;
}

static NSArray *CollectMessages(NSDate *start, NSDate *end, NSInteger limit,
                                NSInteger maxBodyBytes, NSString **errorCode) {
    NSAppleEventDescriptor *arguments = [NSAppleEventDescriptor listDescriptor];
    [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithDate:start] atIndex:1];
    [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithDate:end] atIndex:2];
    [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithInt32:(SInt32)limit]
                         atIndex:3];
    // A Unicode scalar occupies at least one UTF-8 byte, so the byte limit is
    // also a safe upper bound for the AppleScript character fetch. The exact
    // byte limit is enforced below after the AppleEvent result is decoded.
    [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithInt32:(SInt32)maxBodyBytes]
                         atIndex:4];
    NSAppleEventDescriptor *result = ExecuteCollectionHandler(@"collectMessages", arguments,
                                                               errorCode);
    return result ? DecodeCollectedMessages(result, maxBodyBytes, errorCode) : nil;
}

static NSArray *CollectMessageByIdentifier(NSString *sourceIdentifier,
                                           NSInteger maxBodyBytes, NSString **errorCode) {
    NSAppleEventDescriptor *arguments = [NSAppleEventDescriptor listDescriptor];
    [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithString:sourceIdentifier]
                         atIndex:1];
    [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithInt32:(SInt32)maxBodyBytes]
                         atIndex:2];
    NSAppleEventDescriptor *result = ExecuteCollectionHandler(
        @"collectMessageByIdentifier", arguments, errorCode);
    if (!result) return nil;
    NSArray *messages = DecodeCollectedMessages(result, maxBodyBytes, errorCode);
    if (!messages || messages.count > 1) {
        *errorCode = @"mail.incompatible_result";
        return nil;
    }
    return messages;
}

static NSAppleEventDescriptor *StringListDescriptor(NSArray<NSString *> *values) {
    NSAppleEventDescriptor *descriptor = [NSAppleEventDescriptor listDescriptor];
    NSInteger index = 1;
    for (NSString *value in values) {
        [descriptor insertDescriptor:[NSAppleEventDescriptor descriptorWithString:value]
                             atIndex:index];
        index += 1;
    }
    return descriptor;
}

static NSString *SendMail(NSString *account, NSString *sender, NSArray<NSString *> *to,
                          NSArray<NSString *> *cc, NSArray<NSString *> *bcc,
                          NSString *subject, NSString *body, NSString **errorCode) {
    NSAppleScript *script = CompiledMailScript(errorCode);
    if (!script) return nil;
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor
        appleEventWithEventClass:AppleScriptSuite
                         eventID:AppleScriptSubroutine
                targetDescriptor:[NSAppleEventDescriptor currentProcessDescriptor]
                       returnID:kAutoGenerateReturnID
                  transactionID:kAnyTransactionID];
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"sendMessage"]
                   forKeyword:AppleScriptSubroutineName];
    NSAppleEventDescriptor *arguments = [NSAppleEventDescriptor listDescriptor];
    [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithString:account ?: @""]
                         atIndex:1];
    [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithString:sender] atIndex:2];
    [arguments insertDescriptor:StringListDescriptor(to) atIndex:3];
    [arguments insertDescriptor:StringListDescriptor(cc) atIndex:4];
    [arguments insertDescriptor:StringListDescriptor(bcc) atIndex:5];
    [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithString:subject] atIndex:6];
    [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithString:body] atIndex:7];
    [event setParamDescriptor:arguments forKeyword:keyDirectObject];
    NSDictionary *executionError = nil;
    NSAppleEventDescriptor *result = [script executeAppleEvent:event error:&executionError];
    if (!result) {
        NSNumber *number = executionError[NSAppleScriptErrorNumber];
        if (number.integerValue == errAEEventNotPermitted ||
            number.integerValue == errAEEventWouldRequireUserConsent) {
            *errorCode = @"mail.authorization_required";
        } else {
            *errorCode = @"mail.send_failed";
        }
        return nil;
    }
    NSString *status = DescriptorString(result);
    if ([status isEqual:@"application_accepted"]) return status;
    if ([status isEqual:@"sender_not_found"] || [status isEqual:@"account_mismatch"]) {
        *errorCode = @"mail.sender_not_found";
    } else if ([status isEqual:@"sender_ambiguous"]) {
        *errorCode = @"mail.sender_ambiguous";
    } else {
        *errorCode = @"mail.send_failed";
    }
    return nil;
}

static NSDictionary *HandleRequest(NSDictionary *request) {
    NSArray *envelopeKeys = @[@"kind", @"protocol_version", @"request_id", @"operation_id",
                              @"application_contract", @"capability", @"payload", @"deadline_ms", @"idempotency_key",
                              @"policy"];
    if (!ExactKeys(request, envelopeKeys) || ![request[@"kind"] isEqual:@"request"] ||
        ![request[@"protocol_version"] isEqual:ProtocolVersion] ||
        ![request[@"application_contract"] isEqual:ApplicationContract] ||
        !SafeIdentifier(request[@"request_id"]) || !SafeIdentifier(request[@"operation_id"]) ||
        !SafeIdentifier(request[@"capability"]) || !SafeIdentifier(request[@"idempotency_key"]) ||
        ![request[@"payload"] isKindOfClass:[NSDictionary class]] ||
        ![request[@"policy"] isKindOfClass:[NSDictionary class]]) {
        return Failure(@"unknown", @"protocol.invalid_envelope", @"never", @"degraded");
    }
    NSString *requestID = request[@"request_id"];
    NSString *capability = request[@"capability"];
    CurrentOperationID = request[@"operation_id"];
    CurrentCapability = capability;
    NSDictionary *payload = request[@"payload"];
    NSDictionary *policy = request[@"policy"];
    if (!ValidPolicyShape(policy)) {
        return Failure(requestID, @"protocol.invalid_envelope", @"never", @"degraded");
    }

    LogInfo([NSString stringWithFormat:
        @"[worker:mail:request:start] capability=%@", capability]);

    if ([capability isEqual:@"capabilities"]) {
        if (payload.count != 0 || !PolicyMatches(policy, @"read", @"none")) {
            return Failure(requestID, @"protocol.invalid_payload", @"never", @"degraded");
        }
        return Success(requestID, @{
            @"schema": @"sherpa.worker-capabilities.v2",
            @"capabilities": @[
                MailDescriptor(@"mail.script.validate", @"read", @"none"),
                MailDescriptor(@"mail.authorization.status", @"read", @"none"),
                MailDescriptor(@"mail.authorization.request", @"authorization_prompt", @"authorization_readback"),
                MailDescriptor(@"mail.message.send", @"dispatch", @"application_acceptance"),
                MailDescriptor(@"mail.messages.list", @"read", @"none"),
                MailDescriptor(@"mail.message.get", @"read", @"none"),
            ],
        });
    }

    if ([capability isEqual:@"mail.script.validate"]) {
        if (payload.count != 0 || !PolicyMatches(policy, @"read", @"none")) {
            return Failure(requestID, @"protocol.invalid_payload", @"never", @"degraded");
        }
        NSString *errorCode = nil;
        if (!CompiledMailScript(&errorCode)) {
            return Failure(requestID, errorCode, @"never", @"incompatible");
        }
        return Success(requestID, @{@"valid": @YES});
    }

    if ([capability isEqual:@"mail.authorization.status"]) {
        if (payload.count != 0 || !PolicyMatches(policy, @"read", @"none")) {
            return Failure(requestID, @"protocol.invalid_payload", @"never", @"degraded");
        }
        return Success(requestID, @{@"authorization": AuthorizationState(NO)});
    }

    if ([capability isEqual:@"mail.authorization.request"]) {
        BOOL promptEnabled = [[[[NSProcessInfo processInfo] environment]
            objectForKey:@"SHERPA_ALLOW_PERMISSION_PROMPT"] isEqual:@"1"];
        if (payload.count != 0 || !PolicyMatches(policy, @"authorization_prompt", @"authorization_readback") ||
            !promptEnabled) {
            return Failure(requestID, @"mail.permission_prompt_disabled", @"after_user_action",
                           @"disabled");
        }
        return Success(requestID, @{@"authorization": AuthorizationState(YES)});
    }

    if ([capability isEqual:@"mail.message.send"]) {
        NSArray *keys = @[@"account", @"sender", @"to", @"cc", @"bcc", @"subject", @"body"];
        id accountValue = payload[@"account"];
        BOOL validAccount = accountValue == [NSNull null] ||
                            ValidHeader(accountValue, 4096, NO);
        NSArray *to = payload[@"to"];
        NSArray *cc = payload[@"cc"];
        NSArray *bcc = payload[@"bcc"];
        NSUInteger recipientCount = [to isKindOfClass:[NSArray class]] ? to.count : 0;
        if ([cc isKindOfClass:[NSArray class]]) recipientCount += cc.count;
        if ([bcc isKindOfClass:[NSArray class]]) recipientCount += bcc.count;
        if (!ExactKeys(payload, keys) || !PolicyMatches(policy, @"dispatch", @"application_acceptance") ||
            !validAccount || !ValidMailbox(payload[@"sender"]) ||
            !ValidMailboxArray(to) || !ValidMailboxArray(cc) || !ValidMailboxArray(bcc) ||
            to.count == 0 || recipientCount > 256 ||
            !ValidHeader(payload[@"subject"], 16384, YES) ||
            !ValidBoundedString(payload[@"body"], MaxBodyBytes, NO)) {
            return Failure(requestID, @"protocol.invalid_payload", @"never", @"degraded");
        }
        NSString *authorization = AuthorizationState(NO);
        if (![authorization isEqual:@"authorized"]) {
            return Failure(requestID, @"mail.authorization_required", @"after_user_action",
                           @"unavailable");
        }
        NSString *errorCode = nil;
        NSString *accepted = SendMail(
            accountValue == [NSNull null] ? nil : accountValue,
            payload[@"sender"], to, cc, bcc, payload[@"subject"], payload[@"body"],
            &errorCode);
        if (!accepted) {
            NSString *retry = [errorCode isEqual:@"mail.authorization_required"]
                ? @"after_user_action" : @"never";
            return Failure(requestID, errorCode ?: @"mail.send_failed", retry, @"degraded");
        }
        return Success(requestID, @{
            @"channel": @"mail",
            @"transport": @"mail_applescript",
            @"verification": @"application_accepted",
        });
    }

    if ([capability isEqual:@"mail.messages.list"]) {
        NSArray *keys = @[@"from", @"to", @"limit", @"max_body_bytes"];
        if (!ExactKeys(payload, keys) || !PolicyMatches(policy, @"read", @"none")) {
            return Failure(requestID, @"protocol.invalid_payload", @"never", @"degraded");
        }
        NSDate *start = ParseDate(payload[@"from"]);
        NSDate *end = ParseDate(payload[@"to"]);
        NSInteger limit = [payload[@"limit"] integerValue];
        NSInteger bodyBytes = [payload[@"max_body_bytes"] integerValue];
        if (!start || !end || [start compare:end] != NSOrderedAscending || limit < 1 ||
            limit > MaxMessages || bodyBytes < 0 || bodyBytes > MaxBodyBytes) {
            return Failure(requestID, @"protocol.invalid_payload", @"never", @"degraded");
        }
        NSString *authorization = AuthorizationState(NO);
        if (![authorization isEqual:@"authorized"]) {
            return Failure(requestID, @"mail.authorization_required", @"after_user_action",
                           @"unavailable");
        }
        NSString *errorCode = nil;
        NSArray *messages = CollectMessages(start, end, limit, bodyBytes, &errorCode);
        if (!messages) {
            NSString *retry = [errorCode isEqual:@"mail.authorization_required"]
                ? @"after_user_action" : @"safe";
            return Failure(requestID, errorCode ?: @"mail.read_failed", retry, @"degraded");
        }
        return Success(requestID, @{@"messages": messages});
    }

    if ([capability isEqual:@"mail.message.get"]) {
        NSArray *keys = @[@"source_message_id", @"max_body_bytes"];
        if (!ExactKeys(payload, keys) || !PolicyMatches(policy, @"read", @"none") ||
            !ValidBoundedString(payload[@"source_message_id"], 4096, NO)) {
            return Failure(requestID, @"protocol.invalid_payload", @"never", @"degraded");
        }
        NSInteger bodyBytes = [payload[@"max_body_bytes"] integerValue];
        if (bodyBytes < 1 || bodyBytes > MaxBodyBytes) {
            return Failure(requestID, @"protocol.invalid_payload", @"never", @"degraded");
        }
        NSString *authorization = AuthorizationState(NO);
        if (![authorization isEqual:@"authorized"]) {
            return Failure(requestID, @"mail.authorization_required", @"after_user_action",
                           @"unavailable");
        }
        NSString *errorCode = nil;
        NSArray *messages = CollectMessageByIdentifier(payload[@"source_message_id"],
                                                        bodyBytes, &errorCode);
        if (!messages) {
            NSString *retry = [errorCode isEqual:@"mail.authorization_required"]
                ? @"after_user_action" : @"safe";
            return Failure(requestID, errorCode ?: @"mail.read_failed", retry, @"degraded");
        }
        return Success(requestID, @{@"message": messages.firstObject ?: [NSNull null]});
    }

    return Failure(requestID, @"protocol.unsupported_capability", @"never", @"degraded");
}

NSData *SherpaMailHandleRequest(NSData *input) {
    @autoreleasepool {
        NSDictionary *response = nil;
        if (input.length > MaxRequestBytes) {
            response = Failure(@"unknown", @"protocol.request_too_large", @"never", @"degraded");
        } else if (input.length == 0) {
            response = Failure(@"unknown", @"protocol.invalid_envelope", @"never", @"degraded");
        } else {
            NSError *jsonError = nil;
            id decoded = [NSJSONSerialization JSONObjectWithData:input options:0 error:&jsonError];
            if (![decoded isKindOfClass:[NSDictionary class]]) {
                response = Failure(@"unknown", @"protocol.invalid_json", @"never", @"degraded");
            } else {
                response = HandleRequest(decoded);
            }
        }
        NSDictionary *errorResult = [response[@"error"] isKindOfClass:[NSDictionary class]] ? response[@"error"] : nil;
        NSString *code = [errorResult[@"code"] isKindOfClass:[NSString class]] ? errorResult[@"code"] : nil;
        if (code) LogFailure(code);
        NSError *encodeError = nil;
        NSData *output = [NSJSONSerialization dataWithJSONObject:response options:NSJSONWritingSortedKeys
                                                           error:&encodeError];
        if (!output || output.length > MaxResponseBytes) {
            NSDictionary *bounded = Failure(response[@"request_id"], @"context.result_too_large",
                                             @"never", @"degraded");
            output = [NSJSONSerialization dataWithJSONObject:bounded options:NSJSONWritingSortedKeys
                                                        error:nil];
        }
        return output ?: [NSData data];
    }
}

#ifndef SHERPA_MAIL_LIBRARY
int main(void) {
    @autoreleasepool {
        NSData *input = [[NSFileHandle fileHandleWithStandardInput]
            readDataOfLength:MaxRequestBytes + 1];
        NSData *output = SherpaMailHandleRequest(input);
        if (output.length == 0) return EXIT_FAILURE;
        [[NSFileHandle fileHandleWithStandardOutput] writeData:output];
        return EXIT_SUCCESS;
    }
}
#endif
